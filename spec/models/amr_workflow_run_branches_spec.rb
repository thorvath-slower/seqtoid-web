# frozen_string_literal: true

require "rails_helper"

# Coverage Wave 3: branch sweep for AmrWorkflowRun. Targets the else/opposite
# arms of #results (cacheable_only true vs false), #count_per_million (nil
# cached results early-return), and the rescue in #amr_metrics.
RSpec.describe AmrWorkflowRun, type: :model do
  let(:cached) do
    "{\"quality_metrics\": {\"total_reads\": 1000, \"total_ercc_reads\": 0, \"fraction_subsampled\": 1.0}}"
  end

  describe "#results" do
    it "omits report_table_data when cacheable_only is true (skips the unless body)" do
      run = build(:amr_workflow_run, cached_results: cached)
      expect(AmrReportDataService).not_to receive(:call)

      result = run.results(cacheable_only: true)
      expect(result).to have_key("quality_metrics")
      expect(result).not_to have_key("report_table_data")
    end

    it "includes report_table_data when cacheable_only is false (the unless body runs)" do
      run = build(:amr_workflow_run, cached_results: cached)
      allow(AmrReportDataService).to receive(:call).and_return("rows")

      result = run.results(cacheable_only: false)
      expect(result["report_table_data"]).to eq("rows")
    end

    it "falls back to amr_metrics when quality_metrics is not cached (the || right side)" do
      run = build(:amr_workflow_run, cached_results: "{}")
      allow(AmrMetricsService).to receive(:call).and_return("computed")

      result = run.results(cacheable_only: true)
      expect(result["quality_metrics"]).to eq("computed")
    end
  end

  describe "#count_per_million" do
    it "returns nil early when there are no cached quality_metrics (the nil guard then)" do
      run = build(:amr_workflow_run, cached_results: nil)
      expect(run.count_per_million(300)).to be_nil
    end

    it "computes the count when quality_metrics are present (the &.dig truthy path)" do
      run = build(:amr_workflow_run, cached_results: cached)
      # 300 / ((1000 - 0) * 1.0) * 1_000_000 = 300_000.0
      expect(run.count_per_million(300)).to eq(300_000.0)
    end
  end

  describe "#amr_metrics" do
    it "logs and returns nil when the service raises (the rescue)" do
      run = build(:amr_workflow_run, cached_results: "{}")
      allow(AmrMetricsService).to receive(:call).and_raise(RuntimeError)
      expect(LogUtil).to receive(:log_error).with(
        "Error loading counts metrics", hash_including(:exception)
      )

      expect(run.amr_metrics).to be_nil
    end
  end
end
