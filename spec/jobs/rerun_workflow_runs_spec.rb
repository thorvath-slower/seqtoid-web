require "rails_helper"

RSpec.describe RerunWorkflowRuns, type: :job do
  create_users

  let(:project) { create(:project, users: [@joe]) }
  let(:sample) { create(:sample, project: project, user: @joe) }
  let(:short_read_mngs) { WorkflowRun::WORKFLOW[:short_read_mngs] }
  let(:consensus_genome) { WorkflowRun::WORKFLOW[:consensus_genome] }
  let(:amr) { WorkflowRun::WORKFLOW[:amr] }

  describe "#perform" do
    context "for an mNGS workflow (operates on sample ids)" do
      let(:sample2) { create(:sample, project: project, user: @joe) }

      it "sets each sample's status to need_rerun to trigger the rerun callback" do
        samples = [sample, sample2]
        allow(Sample).to receive(:find).with([sample.id, sample2.id]).and_return(samples)
        samples.each do |s|
          expect(s).to receive(:update).with(status: Sample::STATUS_RERUN)
        end

        RerunWorkflowRuns.perform([sample.id, sample2.id], short_read_mngs)
      end
    end

    context "for a non-mNGS workflow (operates on workflow run ids)" do
      let(:wr1) { create(:workflow_run, sample: sample, workflow: consensus_genome) }
      let(:wr2) { create(:workflow_run, sample: sample, workflow: consensus_genome) }

      it "calls rerun on each identified workflow run" do
        runs = [wr1, wr2]
        allow(WorkflowRun).to receive(:find).with([wr1.id, wr2.id]).and_return(runs)
        runs.each { |r| expect(r).to receive(:rerun) }

        RerunWorkflowRuns.perform([wr1.id, wr2.id], consensus_genome)
      end
    end

    context "when an error occurs" do
      it "logs the error and re-raises" do
        allow(WorkflowRun).to receive(:find).and_raise(StandardError.new("boom"))
        expect(LogUtil).to receive(:log_error).with(
          "Failed to rerun workflow runs",
          ids: [1, 2],
          workflow: amr,
          exception: an_instance_of(StandardError)
        )
        expect do
          RerunWorkflowRuns.perform([1, 2], amr)
        end.to raise_error(StandardError, "boom")
      end
    end
  end
end
