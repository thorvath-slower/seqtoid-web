require 'rails_helper'
require 'warden/test/helpers'

# Full-stack request specs for ProjectsController.
#
# Focus: the authorization boundaries that the isolated controller specs don't
# fully exercise through routing — the `power :projects` scoping (a regular user
# cannot read another user's private project => RecordNotFound), the admin-only
# gate on :new/:edit, and the create/update/destroy side effects actually
# landing in the DB. See app/controllers/projects_controller.rb and
# app/models/power.rb (`power :projects` / `power :updatable_projects`).
RSpec.describe "Projects request", type: :request do
  include Warden::Test::Helpers

  create_users

  describe "GET /projects/:id.json (show)" do
    context "when not signed in" do
      it "returns 401 Not Authenticated for the JSON endpoint" do
        project = create(:project, users: [@joe])
        get "/projects/#{project.id}.json"
        # Full-stack: the Warden failure_app (config/initializers/auth0.rb) renders
        # {error: 'Unauthorized', code: 401} before the controller runs, so we get
        # a 401 JSON response rather than ApplicationController's {errors: ['Not
        # Authenticated']} (that branch is only reached in controller specs, which
        # skip the middleware). Either way it's a 401, not a data leak.
        expect(response).to have_http_status(:unauthorized)
        expect(response.media_type).to eq("application/json")
        expect(response.body).to include("Unauthorized")
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
        # A project is viewable by a non-member only when it actually has a PUBLIC
        # sample: Project.viewable scopes on Sample.public_samples (see
        # app/models/project.rb#viewable), not merely on public_access. So the
        # public project needs a sample old enough to have gone public
        # (days_to_keep_sample_private has elapsed) — public_access: 1 alone is not
        # enough. This mirrors how projects_controller_spec sets up public projects.
        public_project = create(:public_project, users: [@admin], samples_data: [{ user: @admin, created_at: 1.year.ago }])

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
      # GET /projects/new renders projects/_form.html.erb, whose first line calls
      # current_user.admin?. The `sign_in` stub only stubs current_user on the
      # ApplicationController instance; it does NOT reach the VIEW's current_user
      # (ApplicationHelper#current_user => warden.user(:auth0_user)), which would be
      # nil and raise "undefined method `admin?' for nil". So we ALSO establish a
      # real Warden session for the view. `sign_in` still passes the auth0 token
      # gate (authenticate_user!/admin_required) that a bare Warden login can't.
      Warden.test_mode!
      sign_in @admin
      login_as @admin, scope: :auth0_user

      get "/projects/new"
      expect(response).to have_http_status(:ok)
    ensure
      Warden.test_reset!
    end
  end

  describe "POST /projects (create)" do
    before do
      sign_in @joe

      # ProjectsController#create runs the real version-pinning side effects
      # (pin_to_major_versions / pin_default_alignment_config /
      # pin_latest_human_version). VersionPinningService writes a
      # ProjectWorkflowVersion whose version_prefix is NOT NULL, so without these
      # app_config/workflow_version rows the pin writes a nil version and the create
      # raises a NOT NULL violation. This mirrors the setup in
      # projects_controller_spec.rb (create_workflow_versions + the create block).
      {
        "consensus-genome" => "3.4.18",
        "short-read-mngs" => "8.2.2",
        "phylotree-ng" => "6.11.0",
        "amr" => "1.2.5",
        "long-read-mngs" => "0.7.3",
      }.each do |workflow, version|
        create(:app_config, key: "#{workflow}-version", value: version)
        create(:workflow_version, workflow: workflow.underscore, version: version)
      end
      create(:app_config, key: AppConfig::DEFAULT_ALIGNMENT_CONFIG_NAME, value: "2021-01-22")
      create(:workflow_version, workflow: HostGenome::HUMAN_HOST, version: "1")
      create(:workflow_version, workflow: HostGenome::HUMAN_HOST, version: "2")
    end

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
