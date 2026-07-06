require 'rails_helper'

RSpec.describe BenchmarkWorkflowRun, type: :model do
  let(:sample) { create(:sample, project: create(:project)) }

  def build_benchmark(inputs_json: nil, cached_results: nil)
    create(:workflow_run,
           sample: sample,
           workflow: WorkflowRun::WORKFLOW[:benchmark],
           inputs_json: inputs_json,
           cached_results: cached_results).becomes(BenchmarkWorkflowRun)
  end

  context "constants" do
    it "exposes the truth files bucket" do
      expect(BenchmarkWorkflowRun::AWS_S3_TRUTH_FILES_BUCKET).to eq("s3://idseq-bench/datasets/truth_files/")
    end
  end

  context "#get_output_name" do
    it "formats the template with the underscored benchmarked workflow name" do
      run = build_benchmark(inputs_json: { "workflow_benchmarked" => "short-read-mngs" }.to_json)
      result = run.get_output_name(BenchmarkWorkflowRun::OUTPUT_BENCHMARK_HTML_TEMPLATE)
      expect(result).to eq("benchmark.short_read_mngs_benchmark.benchmark_html")
    end

    it "handles a nil inputs gracefully" do
      run = build_benchmark(inputs_json: nil)
      result = run.get_output_name(BenchmarkWorkflowRun::OUTPUT_BENCHMARK_TRUTH_NT_TEMPLATE)
      # format() renders the nil workflow name as an empty string.
      expect(result).to eq("benchmark._benchmark.truth_nt")
    end
  end

  context "#results" do
    it "prefers cached benchmark_metrics/info when present" do
      cached = {
        "benchmark_metrics" => { "aupr" => 0.99 },
        "benchmark_info" => { "workflow" => "short-read-mngs" },
        "additional_info" => { "note" => "cached" },
      }.to_json
      run = build_benchmark(
        inputs_json: { "workflow_benchmarked" => "short-read-mngs" }.to_json,
        cached_results: cached
      )
      allow(run).to receive(:output).and_return("<html></html>")

      results = run.results
      expect(results["benchmark_metrics"]).to eq({ "aupr" => 0.99 })
      expect(results["benchmark_info"]).to eq({ "workflow" => "short-read-mngs" })
      expect(results["additional_info"]).to eq({ "note" => "cached" })
      expect(results).to have_key("benchmark_html_report")
    end

    it "omits the html report when cacheable_only is true" do
      run = build_benchmark(
        inputs_json: { "workflow_benchmarked" => "short-read-mngs" }.to_json,
        cached_results: { "benchmark_metrics" => {}, "benchmark_info" => {}, "additional_info" => {} }.to_json
      )
      results = run.results(cacheable_only: true)
      expect(results).not_to have_key("benchmark_html_report")
    end

    it "falls back to computing benchmark_metrics via the service and logs on error" do
      run = build_benchmark(inputs_json: { "workflow_benchmarked" => "consensus-genome" }.to_json)
      allow(BenchmarkMetricsService).to receive(:call).and_raise(StandardError.new("boom"))
      allow(LogUtil).to receive(:log_error)
      allow(run).to receive(:output).and_return(nil)

      results = run.results
      expect(results["benchmark_metrics"]).to be_nil
      expect(LogUtil).to have_received(:log_error).with(
        "Error loading benchmark metrics", hash_including(:exception, :workflow_run_id)
      )
    end
  end
end
