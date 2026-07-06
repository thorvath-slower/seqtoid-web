require "rails_helper"

RSpec.describe WorkflowRunValidationService, type: :service do
  create_users

  before do
    # @joe's own project + sample + workflow run (viewable to @joe)
    @joe_project = create(:project, users: [@joe])
    @joe_sample = create(:sample, project: @joe_project, user: @joe)
    @joe_workflow_run = create(:workflow_run, sample: @joe_sample, user: @joe)

    # A private project owned by another user; not viewable to @joe
    other_user = create(:user)
    @private_project = create(:project, users: [other_user])
    @private_sample = create(:sample, project: @private_project, user: other_user)
    @private_workflow_run = create(:workflow_run, sample: @private_sample, user: other_user)
  end

  describe "#call" do
    context "when the user has access to all requested workflow runs" do
      it "returns the viewable WorkflowRun records with no error" do
        result = WorkflowRunValidationService.call(query_ids: [@joe_workflow_run.id], current_user: @joe)

        expect(result[:error]).to be_nil
        expect(result[:viewable_workflow_runs].map(&:id)).to contain_exactly(@joe_workflow_run.id)
        expect(result[:viewable_workflow_runs].first).to be_a(WorkflowRun)
      end
    end

    context "when the user requests workflow runs they cannot access" do
      it "filters out the inaccessible workflow runs without raising an error" do
        result = WorkflowRunValidationService.call(
          query_ids: [@joe_workflow_run.id, @private_workflow_run.id],
          current_user: @joe
        )

        expect(result[:error]).to be_nil
        expect(result[:viewable_workflow_runs].map(&:id)).to contain_exactly(@joe_workflow_run.id)
      end
    end

    context "when query_ids is empty" do
      it "returns an empty viewable_workflow_runs array" do
        result = WorkflowRunValidationService.call(query_ids: [], current_user: @joe)

        expect(result[:error]).to be_nil
        expect(result[:viewable_workflow_runs]).to be_empty
      end
    end

    context "when query_ids is nil" do
      it "treats it as an empty request and returns no workflow runs" do
        result = WorkflowRunValidationService.call(query_ids: nil, current_user: @joe)

        expect(result[:error]).to be_nil
        expect(result[:viewable_workflow_runs]).to be_empty
      end
    end

    context "when query_ids are strings" do
      it "coerces them to integers and still resolves access" do
        result = WorkflowRunValidationService.call(query_ids: [@joe_workflow_run.id.to_s], current_user: @joe)

        expect(result[:error]).to be_nil
        expect(result[:viewable_workflow_runs].map(&:id)).to contain_exactly(@joe_workflow_run.id)
      end
    end

    context "when an unexpected error occurs while validating access" do
      it "captures the error and returns WORKFLOW_RUN_ACCESS_ERROR" do
        allow(Power).to receive(:new).and_raise(StandardError.new("boom"))

        result = WorkflowRunValidationService.call(query_ids: [@joe_workflow_run.id], current_user: @joe)

        expect(result[:error]).to eq(WorkflowRunValidationService::WORKFLOW_RUN_ACCESS_ERROR)
        expect(result[:viewable_workflow_runs]).to be_empty
      end
    end
  end
end
