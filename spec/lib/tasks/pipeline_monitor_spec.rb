require "rails_helper"

# CheckPipelineRuns is defined in lib/tasks/pipeline_monitor.rake, which is loaded
# via Rails.application.load_tasks in rails_helper. These specs cover the defensive
# guards added for Forgejo #388 (the empty/blank JSON body was 532 Sentry events).
RSpec.describe CheckPipelineRuns do
  describe ".parse_json_or_nil" do
    it "returns nil for a blank body without raising" do
      expect(LogUtil).not_to receive(:log_error)
      expect(described_class.parse_json_or_nil("", "test")).to be_nil
      expect(described_class.parse_json_or_nil(nil, "test")).to be_nil
      expect(described_class.parse_json_or_nil("   ", "test")).to be_nil
    end

    it "returns nil and logs for an unparseable body instead of raising" do
      expect(LogUtil).to receive(:log_error).with(/Failed to parse JSON/, hash_including(:exception))
      expect(described_class.parse_json_or_nil("{not json", "test")).to be_nil
    end

    it "parses valid JSON" do
      expect(described_class.parse_json_or_nil('{"a":1}', "test")).to eq("a" => 1)
    end
  end

  describe ".benchmark_update" do
    it "no-ops on an empty benchmark config body instead of raising JSON::ParserError" do
      # Simulate `aws s3 cp ... -` returning an empty body (missing object / creds hiccup).
      allow(described_class).to receive(:`).and_return("")
      expect { described_class.benchmark_update(Time.now.to_f) }.not_to raise_error
    end

    it "no-ops when the config is present but has no active_benchmarks" do
      allow(described_class).to receive(:`).and_return('{"defaults":{}}')
      expect { described_class.benchmark_update(Time.now.to_f) }.not_to raise_error
    end
  end

  # A polling sandbox must poll each PipelineRun with the same per-technology branch the
  # notification handler uses: nanopore (single-stage SFN) via update_single_stage_run_status,
  # illumina (multi-stage) via update_job_status. Wrong method => nanopore never leaves RUNNING.
  describe ".update_jobs polling by technology" do
    before do
      allow(AppConfigHelper).to receive(:get_app_config)
        .with(AppConfig::ENABLE_SFN_NOTIFICATIONS).and_return("0")
    end

    it "polls a nanopore run via the single-stage method" do
      pr = instance_double(PipelineRun, id: 11, sample_id: 1, technology: PipelineRun::TECHNOLOGY_INPUT[:nanopore])
      allow(PipelineRun).to receive(:find_by).with(id: 11).and_return(pr)
      expect(pr).to receive(:update_single_stage_run_status)
      expect(pr).not_to receive(:update_job_status)
      described_class.update_jobs(1, 0, [11])
    end

    it "polls an illumina run via the multi-stage method" do
      pr = instance_double(PipelineRun, id: 12, sample_id: 1, technology: PipelineRun::TECHNOLOGY_INPUT[:illumina])
      allow(PipelineRun).to receive(:find_by).with(id: 12).and_return(pr)
      expect(pr).to receive(:update_job_status)
      expect(pr).not_to receive(:update_single_stage_run_status)
      described_class.update_jobs(1, 0, [12])
    end
  end

  # A POLLING sandbox has no shoryuken to consume SFN notifications, so WorkflowRuns
  # (consensus-genome / amr / benchmark) must be polled here, exactly as the mNGS PipelineRuns
  # are -- otherwise their status never leaves RUNNING. Guarded by ENABLE_SFN_NOTIFICATIONS so
  # dev/staging/prod (notification mode) are untouched.
  describe ".update_workflow_run_jobs" do
    let(:workflow_run) { instance_double(WorkflowRun, id: 7, sample_id: 3) }
    let(:running) { instance_double(ActiveRecord::Relation, pluck: [7]) }

    it "polls running WorkflowRuns when notifications are DISABLED (a polling sandbox)" do
      allow(AppConfigHelper).to receive(:get_app_config)
        .with(AppConfig::ENABLE_SFN_NOTIFICATIONS).and_return("0")
      allow(WorkflowRun).to receive(:in_progress).and_return(running)
      allow(WorkflowRun).to receive(:find_by).with(id: 7).and_return(workflow_run)
      expect(workflow_run).to receive(:update_status)
      described_class.update_workflow_run_jobs
    end

    it "does NOT poll when notifications are ENABLED (dev/staging/prod)" do
      allow(AppConfigHelper).to receive(:get_app_config)
        .with(AppConfig::ENABLE_SFN_NOTIFICATIONS).and_return("1")
      expect(WorkflowRun).not_to receive(:in_progress)
      described_class.update_workflow_run_jobs
    end

    it "logs and continues if one WorkflowRun update raises (never aborts the loop)" do
      allow(AppConfigHelper).to receive(:get_app_config)
        .with(AppConfig::ENABLE_SFN_NOTIFICATIONS).and_return("0")
      allow(WorkflowRun).to receive(:in_progress).and_return(running)
      allow(WorkflowRun).to receive(:find_by).with(id: 7).and_return(workflow_run)
      allow(workflow_run).to receive(:update_status).and_raise(StandardError, "boom")
      expect(LogUtil).to receive(:log_error)
        .with(/Updating workflow run 7 failed/, hash_including(:exception))
      expect { described_class.update_workflow_run_jobs }.not_to raise_error
    end
  end
end
