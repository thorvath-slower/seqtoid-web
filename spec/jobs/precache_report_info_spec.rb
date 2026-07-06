require "rails_helper"

RSpec.describe PrecacheReportInfo, type: :job do
  create_users

  describe "#perform" do
    let(:project) { create(:project, users: [@joe]) }
    let(:sample) { create(:sample, project: project, user: @joe) }
    let(:pipeline_run) { create(:pipeline_run, sample: sample) }

    it "invokes precache_report_info! on the identified PipelineRun" do
      expect(PipelineRun).to receive(:find).with(pipeline_run.id).and_return(pipeline_run)
      expect(pipeline_run).to receive(:precache_report_info!)
      PrecacheReportInfo.perform(pipeline_run.id)
    end

    context "when precaching fails" do
      before do
        allow(PipelineRun).to receive(:find).with(pipeline_run.id).and_return(pipeline_run)
        allow(pipeline_run).to receive(:precache_report_info!).and_raise(StandardError.new("boom"))
      end

      it "logs the error and re-raises so the on_failure hook fires" do
        expect(LogUtil).to receive(:log_error).with(
          "PipelineRun #{pipeline_run.id} failed to precache report",
          exception: an_instance_of(StandardError),
          pipeline_run_id: pipeline_run.id
        )
        expect do
          PrecacheReportInfo.perform(pipeline_run.id)
        end.to raise_error(StandardError, "boom")
      end
    end

    it "logs and raises RecordNotFound when the pipeline run does not exist" do
      expect(LogUtil).to receive(:log_error).with(
        "PipelineRun -1 failed to precache report",
        exception: an_instance_of(ActiveRecord::RecordNotFound),
        pipeline_run_id: -1
      )
      expect do
        PrecacheReportInfo.perform(-1)
      end.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
