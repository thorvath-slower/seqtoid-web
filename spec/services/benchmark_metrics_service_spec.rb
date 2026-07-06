require "rails_helper"

RSpec.describe BenchmarkMetricsService, type: :service do
  let(:sample) { create(:sample, project: create(:project)) }

  def build_benchmark_run(inputs)
    create(
      :workflow_run,
      sample: sample,
      workflow: WorkflowRun::WORKFLOW[:benchmark],
      inputs_json: inputs.to_json
    )
  end

  describe "#call" do
    context "when the benchmarked workflow is not short-read-mngs" do
      it "returns an empty metrics hash" do
        run = build_benchmark_run(workflow_benchmarked: WorkflowRun::WORKFLOW[:consensus_genome])

        expect(BenchmarkMetricsService.call(run)).to eq({})
      end
    end

    context "when short-read-mngs with a ground truth file and outputs present" do
      let(:nt_output) { { "aupr" => { "aupr" => 0.987654 }, "l2_norm" => 0.123456 }.to_json }
      let(:nr_output) { { "aupr" => { "aupr" => 0.876543 }, "l2_norm" => 0.234567 }.to_json }

      it "returns rounded AUPR, L2 norm and correlation metrics" do
        run = build_benchmark_run(
          workflow_benchmarked: WorkflowRun::WORKFLOW[:short_read_mngs],
          ground_truth_file: "s3://bucket/truth.tsv"
        )

        allow_any_instance_of(BenchmarkWorkflowRun).to receive(:output) do |instance, key|
          case key
          when /truth_nt/ then nt_output
          when /truth_nr/ then nr_output
          when /correlation/ then "0.95"
          end
        end

        metrics = BenchmarkMetricsService.call(run)

        expect(metrics[:nt_aupr]).to eq(0.9877)
        expect(metrics[:nt_l2_norm]).to eq(0.1235)
        expect(metrics[:nr_aupr]).to eq(0.8765)
        expect(metrics[:nr_l2_norm]).to eq(0.2346)
        expect(metrics[:correlation]).to eq(0.95)
      end
    end

    context "when short-read-mngs without a ground truth file" do
      it "returns nil AUPR/L2 metrics but still resolves correlation" do
        run = build_benchmark_run(workflow_benchmarked: WorkflowRun::WORKFLOW[:short_read_mngs])

        allow_any_instance_of(BenchmarkWorkflowRun).to receive(:output) do |_instance, key|
          key =~ /correlation/ ? "0.42" : nil
        end

        metrics = BenchmarkMetricsService.call(run)

        expect(metrics[:nt_aupr]).to be_nil
        expect(metrics[:nt_l2_norm]).to be_nil
        expect(metrics[:nr_aupr]).to be_nil
        expect(metrics[:nr_l2_norm]).to be_nil
        expect(metrics[:correlation]).to eq(0.42)
      end
    end

    context "when the correlation output is missing" do
      it "sets correlation to nil without raising" do
        run = build_benchmark_run(workflow_benchmarked: WorkflowRun::WORKFLOW[:short_read_mngs])

        allow_any_instance_of(BenchmarkWorkflowRun).to receive(:output) do |_instance, key|
          raise SfnExecution::OutputNotFoundError.new(key, "s3://bucket/description.json") if key =~ /correlation/

          nil
        end

        metrics = BenchmarkMetricsService.call(run)
        expect(metrics[:correlation]).to be_nil
      end
    end
  end
end
