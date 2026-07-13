require "rails_helper"

# Coverage Wave 5: ResultMonitorLoader loads a single pipeline output from S3 into
# the DB, with two top-level modes gated on ENABLE_SFN_NOTIFICATIONS:
#  - notifications ON: retry loop (success / already-loaded / error-with-retries)
#  - notifications OFF: single attempt that re-raises on failure
# We stub the actual loader call (pipeline_run.send(loader)) and AppConfigHelper,
# and stub sleep so the error paths don't actually block.
RSpec.describe ResultMonitorLoader, type: :job do
  create_users

  let(:project) { create(:project, users: [@joe]) }
  let(:sample) { create(:sample, project: project, user: @joe) }
  let(:pipeline_run) { create(:pipeline_run, sample: sample) }
  let(:output) { "ercc_counts" }

  def output_state
    pipeline_run.output_states.find_by(output: output)
  end

  before do
    # Loader is invoked via pipeline_run.send("db_load_ercc_counts"); no-op it.
    allow_any_instance_of(PipelineRun).to receive(:db_load_ercc_counts).and_return(true)
    allow_any_instance_of(described_class).to receive(:sleep) # class method context, harmless
    allow(described_class).to receive(:sleep)
    allow(LogUtil).to receive(:log_error)
  end

  context "with SFN notifications disabled" do
    before do
      allow(AppConfigHelper).to receive(:get_app_config).with(AppConfig::ENABLE_SFN_NOTIFICATIONS).and_return("0")
    end

    it "loads the output and marks it LOADED" do
      ResultMonitorLoader.perform(pipeline_run.id, output)
      expect(output_state.state).to eq(PipelineRun::STATUS_LOADED)
    end

    it "marks LOADING_ERROR and re-raises when the loader fails" do
      allow_any_instance_of(PipelineRun).to receive(:db_load_ercc_counts).and_raise(StandardError, "load failed")
      expect { ResultMonitorLoader.perform(pipeline_run.id, output) }.to raise_error(StandardError, "load failed")
      expect(output_state.state).to eq(PipelineRun::STATUS_LOADING_ERROR)
      expect(LogUtil).to have_received(:log_error)
    end
  end

  context "with SFN notifications enabled" do
    before do
      allow(AppConfigHelper).to receive(:get_app_config).with(AppConfig::ENABLE_SFN_NOTIFICATIONS).and_return("1")
      # finalize_pipeline_run_results calls all_output_states_terminal?; keep it from finalizing.
      allow_any_instance_of(PipelineRun).to receive(:all_output_states_terminal?).and_return(false)
    end

    it "loads the output successfully and breaks out of the retry loop" do
      ResultMonitorLoader.perform(pipeline_run.id, output)
      expect(output_state.state).to eq(PipelineRun::STATUS_LOADED)
    end

    it "breaks quietly when the output was already loaded (RecordNotUnique)" do
      allow_any_instance_of(PipelineRun).to receive(:db_load_ercc_counts)
        .and_raise(ActiveRecord::RecordNotUnique, "duplicate")
      expect { ResultMonitorLoader.perform(pipeline_run.id, output) }.not_to raise_error
    end

    it "retries on transient errors and marks FAILED after MAX_ATTEMPTS" do
      allow_any_instance_of(PipelineRun).to receive(:db_load_ercc_counts).and_raise(StandardError, "transient")
      allow_any_instance_of(PipelineRun).to receive(:all_output_states_terminal?).and_return(false)
      ResultMonitorLoader.perform(pipeline_run.id, output)
      expect(output_state.state).to eq(PipelineRun::STATUS_FAILED)
      # log_error called on each attempt plus the final failure message.
      expect(LogUtil).to have_received(:log_error).at_least(:twice)
    end
  end

  describe ".finalize_pipeline_run_results" do
    it "finalizes when all output states are terminal" do
      allow(pipeline_run).to receive(:all_output_states_terminal?).and_return(true)
      allow(pipeline_run).to receive(:check_job_stats).and_return(nil)
      expect(pipeline_run).to receive(:finalize_results).with(nil)
      described_class.finalize_pipeline_run_results(pipeline_run)
    end

    it "does nothing when output states are not all terminal" do
      allow(pipeline_run).to receive(:all_output_states_terminal?).and_return(false)
      expect(pipeline_run).not_to receive(:finalize_results)
      described_class.finalize_pipeline_run_results(pipeline_run)
    end
  end
end
