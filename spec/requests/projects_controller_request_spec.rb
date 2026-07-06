require 'rails_helper'

# Additional full-stack request specs for ProjectsController, complementing
# spec/requests/project_request_spec.rb. Focuses on the discovery index JSON,
# the read/edit member endpoints (validate_project_name, all_users,
# validate_sample_names) and the admin destroy override. See
# app/controllers/projects_controller.rb and its READ/EDIT_ACTIONS scoping.
RSpec.describe "Projects (extended) request", type: :request do
  create_users

  describe "GET /projects.json (index)" do
    it "requires authentication (401 JSON via Warden failure_app)" do
      get "/projects.json", params: { domain: "my_data" }
      expect(response).to have_http_status(:unauthorized)
      expect(response.body).to include("Unauthorized")
    end

    it "returns the user's projects in the my_data domain" do
      sign_in @joe
      project = create(:project, users: [@joe])

      get "/projects.json", params: { domain: "my_data", listAllIds: true }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["projects"].map { |p| p["id"] }).to include(project.id)
      expect(body["all_projects_ids"]).to include(project.id)
    end
  end

  describe "GET /projects/:id/validate_project_name" do
    before { sign_in @joe }

    it "reports valid for an unused name" do
      project = create(:project, users: [@joe])

      get "/projects/#{project.id}/validate_project_name", params: { name: "A Totally Fresh Name" }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["valid"]).to be(true)
      expect(body["sanitizedName"]).to eq("A Totally Fresh Name")
    end

    it "reports invalid for a name already taken by another project" do
      project = create(:project, users: [@joe])
      taken = create(:project, users: [@joe], name: "Taken Name")

      get "/projects/#{project.id}/validate_project_name", params: { name: taken.name }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["valid"]).to be(false)
      expect(body["message"]).to match(/already taken/i)
    end
  end

  describe "GET /projects/:id/all_users (edit-scoped)" do
    it "returns the member list for a project the user can edit" do
      sign_in @joe
      project = create(:project, users: [@joe])

      get "/projects/#{project.id}/all_users"

      expect(response).to have_http_status(:ok)
      emails = JSON.parse(response.body)["users"].map { |u| u["email"] }
      expect(emails).to include(@joe.email)
    end

    it "raises RecordNotFound for another user's project (updatable_projects scoping)" do
      sign_in @joe
      other = create(:project, users: [@admin])

      expect do
        get "/projects/#{other.id}/all_users"
      end.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "GET /projects/:id/validate_sample_names (read-scoped)" do
    before { sign_in @joe }

    it "de-duplicates names that collide with existing samples in the project" do
      project = create(:project, users: [@joe])
      create(:sample, project: project, user: @joe, name: "dup_sample")

      get "/projects/#{project.id}/validate_sample_names", params: { sample_names: ["dup_sample", "unique_sample"] }

      expect(response).to have_http_status(:ok)
      names = JSON.parse(response.body)
      expect(names).to eq(["dup_sample_1", "unique_sample"])
    end
  end

  describe "DELETE /projects/:id (admin can delete a non-empty project)" do
    it "lets an admin destroy a project that still has samples" do
      sign_in @admin
      project = create(:project, users: [@admin])
      create(:sample, project: project, user: @admin)

      expect do
        delete "/projects/#{project.id}.json"
      end.to change(Project, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end
  end
end
