require 'rails_helper'

# Full-stack request specs for WorkflowRunsController.
#
# Focus: the read authorization boundary (set_workflow_run scopes via
# current_power.workflow_runs and renders 404 for non-viewable runs rather than
# raising), the admin-only :rerun gate, and that the POST batch endpoints filter
# to viewable objects. See app/controllers/workflow_runs_controller.rb and
# app/models/power.rb (`power :workflow_runs`).
RSpec.describe "WorkflowRuns request", type: :request do
  create_users

  let(:consensus_genome) { WorkflowRun::WORKFLOW[:consensus_genome] }

  def workflow_run_for(user)
    project = create(:project, users: [user])
    sample = create(:sample, project: project, user: user)
    create(:workflow_run, sample: sample, user: user, workflow: consensus_genome)
  end

  describe "GET /workflow_runs/:id (show)" do
    context "when not signed in" do
      it "redirects to login" do
        wr = workflow_run_for(@joe)
        get "/workflow_runs/#{wr.id}"
        expect(response).to have_http_status(:redirect)
      end
    end

    context "when signed in as a regular user" do
      before { sign_in @joe }

      it "returns a workflow run the user can view" do
        wr = workflow_run_for(@joe)

        get "/workflow_runs/#{wr.id}"

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)["id"]).to eq(wr.id)
      end

      it "returns 404 (not a leak) for a workflow run on another user's private sample" do
        other = workflow_run_for(@admin)

        get "/workflow_runs/#{other.id}"

        expect(response).to have_http_status(:not_found)
        expect(JSON.parse(response.body)["status"]).to eq("Workflow Run not found")
      end

      it "returns 404 for a non-existent workflow run id" do
        get "/workflow_runs/0"
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "PUT /workflow_runs/:id/rerun (admin-only)" do
    it "redirects a regular user to root_path (admin_required)" do
      sign_in @joe
      wr = workflow_run_for(@joe)

      put "/workflow_runs/#{wr.id}/rerun"

      expect(response).to redirect_to(root_path)
    end
  end

  describe "POST /workflow_runs/created_by_current_user" do
    before { sign_in @joe }

    it "reports true only when every id was created by the current user" do
      mine = workflow_run_for(@joe)

      post "/workflow_runs/created_by_current_user", params: { workflowRunIds: [mine.id] }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["created_by_current_user"]).to be(true)
    end

    it "reports false when an id belongs to another user (not viewable / not created by user)" do
      mine = workflow_run_for(@joe)
      theirs = workflow_run_for(@admin)

      post "/workflow_runs/created_by_current_user", params: { workflowRunIds: [mine.id, theirs.id] }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["created_by_current_user"]).to be(false)
    end
  end

  describe "POST /workflow_runs/workflow_runs_info" do
    before { sign_in @joe }

    it "returns info only for workflow runs the user can view" do
      mine = workflow_run_for(@joe)
      theirs = workflow_run_for(@admin)

      post "/workflow_runs/workflow_runs_info", params: { workflowRunIds: [mine.id, theirs.id] }

      expect(response).to have_http_status(:ok)
      returned_ids = JSON.parse(response.body)["workflowRunInfo"].map { |info| info["id"] }
      expect(returned_ids).to include(mine.id)
      expect(returned_ids).not_to include(theirs.id)
    end
  end
end
