# frozen_string_literal: true

require "rails_helper"

# Coverage Wave 3: branch sweep for PhyloTreeNg. Targets the branch outcomes
# the main spec leaves untaken: update_status when input_error is present
# (succeeded_with_issue) and when the status is unchanged, input_error's
# INPUT_ERRORS match, create_visualization's already-exists else, and
# cleanup_s3's blank-prefix early return.
RSpec.describe PhyloTreeNg, type: :model do
  let(:arn) { "fake:sfn:execution:arn:x".freeze }

  before do
    project = create(:project)
    s1 = create(:sample, project: project)
    s2 = create(:sample, project: project)
    @pr1 = create(:pipeline_run, sample: s1)
    @pr2 = create(:pipeline_run, sample: s2)
    @inputs = { pipeline_run_ids: [@pr1.id, @pr2.id], tax_id: 1 }
  end

  describe "#update_status" do
    it "maps a failure with a known input_error to succeeded_with_issue (the present branch)" do
      tree = create(:phylo_tree_ng, name: "t", status: WorkflowRun::STATUS[:running],
                                    sfn_execution_arn: arn, inputs_json: @inputs)
      allow(tree).to receive(:input_error).and_return({ label: "TooDivergentError", message: "x" })

      tree.update_status("FAILED")
      expect(tree.status).to eq(WorkflowRun::STATUS[:succeeded_with_issue])
    end

    it "does not update when the remote status equals the current status (the != else)" do
      tree = create(:phylo_tree_ng, name: "t", status: WorkflowRun::STATUS[:succeeded],
                                    sfn_execution_arn: arn, inputs_json: @inputs)
      expect(tree).not_to receive(:update)

      tree.update_status(WorkflowRun::STATUS[:succeeded])
    end
  end

  describe "#input_error" do
    it "returns the label/message hash when the SFN error is a known INPUT_ERROR (the if body)" do
      tree = create(:phylo_tree_ng, name: "t", status: WorkflowRun::STATUS[:failed],
                                    sfn_execution_arn: arn, inputs_json: @inputs)
      fake_exec = instance_double(SfnExecution, error: "TooDivergentError")
      allow(tree).to receive(:sfn_execution).and_return(fake_exec)

      expect(tree.input_error).to eq(
        label: "TooDivergentError",
        message: PhyloTreeNg::INPUT_ERRORS["TooDivergentError"]
      )
    end

    it "returns nil when the SFN error is not a known INPUT_ERROR (the implicit else)" do
      tree = create(:phylo_tree_ng, name: "t", status: WorkflowRun::STATUS[:failed],
                                    sfn_execution_arn: arn, inputs_json: @inputs)
      fake_exec = instance_double(SfnExecution, error: "SomethingElse")
      allow(tree).to receive(:sfn_execution).and_return(fake_exec)

      expect(tree.input_error).to be_nil
    end
  end

  describe "#create_visualization (via after_create)" do
    it "logs when a visualization already exists (the else branch)" do
      tree = build(:phylo_tree_ng, name: "dup", status: WorkflowRun::STATUS[:running],
                                   inputs_json: @inputs)
      # Pre-create the visualization the after_create hook would look for.
      # The id isn't known until save, so intercept: force the empty? check false.
      allow(Visualization).to receive(:where).and_call_original
      fake_relation = double("relation", empty?: false, ids: [42])
      allow(Visualization).to receive(:where).with(data: hash_including("treeNgId")).and_return(fake_relation)
      expect(Rails.logger).to receive(:error).with(match(/VisualizationCreationError/))

      tree.save!
    end
  end

  describe "#cleanup_s3 (via before_destroy)" do
    it "returns early without calling S3 when the prefix is blank (the blank guard)" do
      tree = create(:phylo_tree_ng, name: "t", status: WorkflowRun::STATUS[:running],
                                    sfn_execution_arn: arn, inputs_json: @inputs,
                                    s3_output_prefix: nil)
      expect(S3Util).not_to receive(:delete_s3_prefix)

      tree.destroy
    end
  end

  describe "#finalized?" do
    it "is true for a succeeded_with_issue status and false for running" do
      tree = build(:phylo_tree_ng, status: WorkflowRun::STATUS[:succeeded_with_issue])
      expect(tree.finalized?).to be true
      tree.status = WorkflowRun::STATUS[:running]
      expect(tree.finalized?).to be false
    end
  end
end
