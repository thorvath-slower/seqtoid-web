require 'rails_helper'

# Full-stack request specs for ProjectsController.
#
# Focus: the authorization boundaries that the isolated controller specs don't
# fully exercise through routing — the `power :projects` scoping (a regular user
# cannot read another user's private project => RecordNotFound), the admin-only
# gate on :new/:edit, and the create/update/destroy side effects actually
# landing in the DB. See app/controllers/projects_controller.rb and
# app/models/power.rb (`power :projects` / `power :updatable_projects`).
RSpec.describe "Projects request", type: :request do
  create_users

  describe "GET /projects/:id.json (show)" do
    context "when not signed in" do
      it "returns 401 Not Authenticated for the JSON endpoint" do
        project = create(:project, users: [@joe])
        get "/projects/#{project.id}.json"
        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)["errors"]).to include("Not Authenticated")
      end
    end

    context "when signed in as a regular user" do
      before { sign_in @joe }

      it "returns a project the user is a member of, with the real record's fields" do
        project = create(:project, users: [@joe], description: "Joe's project")

        get "/projects/#{project.id}.json"

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        # Derive expectations from the actual record, not hardcoded values.
        expect(body["id"]).to eq(project.id)
        expect(body["name"]).to eq(project.name)
        expect(body["description"]).to eq(project.description)
        expect(body["public_access"]).to eq(project.public_access.to_i)
      end

      it "returns a public project owned by another user" do
        public_project = create(:public_project, users: [@admin])

        get "/projects/#{public_project.id}.json"

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)["id"]).to eq(public_project.id)
      end

      it "raises RecordNotFound for another user's PRIVATE project (power scoping)" do
        private_other = create(:project, users: [@admin], public_access: 0)

        expect do
          get "/projects/#{private_other.id}.json"
        end.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end

  describe "GET /projects/new (admin-only)" do
    it "redirects a regular user to root_path" do
      sign_in @joe
      get "/projects/new"
      expect(response).to redirect_to(root_path)
    end

    it "allows an admin" do
      sign_in @admin
      get "/projects/new"
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /projects (create)" do
    before { sign_in @joe }

    it "creates a project owned by the current user" do
      expect do
        post "/projects.json", params: { project: { name: "Brand New Project", public_access: 0, description: "hi" } }
      end.to change(Project, :count).by(1)

      expect(response).to have_http_status(:created)
      created = Project.order(:id).last
      # The creator must be attached as a member and recorded as creator.
      expect(created.users).to include(@joe)
      expect(created.creator_id).to eq(@joe.id)
    end

    it "returns unprocessable_content with the model errors when name is missing" do
      post "/projects.json", params: { project: { public_access: 0 } }

      expect(response).to have_http_status(:unprocessable_content)
      # Body is the list of full error messages.
      expect(JSON.parse(response.body)).to be_an(Array)
      expect(JSON.parse(response.body).join).to match(/name/i)
    end
  end

  describe "PUT /projects/:id/update_project_visibility" do
    before { sign_in @joe }

    it "updates visibility on a project the user can edit" do
      project = create(:project, users: [@joe], public_access: 0)

      put "/projects/#{project.id}/update_project_visibility", params: { public_access: 1 }

      expect(response).to have_http_status(:ok)
      expect(project.reload.public_access).to eq(1)
    end

    it "raises RecordNotFound when editing another user's project (updatable_projects scoping)" do
      other = create(:project, users: [@admin], public_access: 0)

      expect do
        put "/projects/#{other.id}/update_project_visibility", params: { public_access: 1 }
      end.to raise_error(ActiveRecord::RecordNotFound)

      # The other user's project must be unchanged.
      expect(other.reload.public_access).to eq(0)
    end
  end

  describe "DELETE /projects/:id (destroy)" do
    before { sign_in @joe }

    it "destroys an empty project the user owns" do
      project = create(:project, users: [@joe])

      expect do
        delete "/projects/#{project.id}.json"
      end.to change(Project, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end

    it "refuses to destroy a project that still has samples (non-admin)" do
      project = create(:project, users: [@joe])
      create(:sample, project: project, user: @joe)

      expect do
        delete "/projects/#{project.id}.json"
      end.not_to change(Project, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["message"]).to eq("Cannot delete this project")
    end
  end
end
