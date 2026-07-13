require 'rails_helper'
require 'json'

require "support/common_stub_constants"

RSpec.describe SfnBenchmarkPipelineDispatchService, type: :service do
  let(:benchmark_workflow) { WorkflowRun::WORKFLOW[:benchmark] }
  let(:short_read_workflow) { WorkflowRun::WORKFLOW[:short_read_mngs] }
  let(:fake_benchmark_version) { "1.0.0" }
  let(:fake_output_prefix) { "s3://fake-bucket/output/prefix" }

  let(:project) { create(:project) }
  let(:sample) { create(:sample, project: project) }

  let(:dispatch_output) do
    { sfn_execution_arn: CommonStubConstants::FAKE_SFN_EXECUTION_ARN, sfn_input_json: {} }
  end

  # Build a benchmark workflow run with the given inputs hash.
  def build_benchmark_run(inputs)
    create(:workflow_run, sample: sample, workflow: benchmark_workflow, inputs_json: inputs.to_json)
  end

  before do
    # The generic dispatch is exercised in its own spec; stub the seam here.
    allow(SfnGenericDispatchService).to receive(:call).and_return(dispatch_output)
    allow(AppConfigHelper).to receive(:get_workflow_version).and_call_original
    allow(AppConfigHelper).to receive(:get_workflow_version)
      .with(benchmark_workflow).and_return(fake_benchmark_version)
    # sfn_output_path reads sample.sample_output_s3_path; keep it deterministic.
    allow_any_instance_of(BenchmarkWorkflowRun).to receive(:sfn_output_path).and_return(fake_output_prefix)
  end

  describe "#call" do
    context "for a non-mngs benchmark (no per-run output files)" do
      let(:workflow_run) do
        build_benchmark_run(
          "workflow_benchmarked" => WorkflowRun::WORKFLOW[:consensus_genome],
          "ground_truth_file" => "s3://truth/ground_truth.tsv",
          "run_ids" => []
        )
      end

      subject { SfnBenchmarkPipelineDispatchService.call(workflow_run) }

      it "dispatches with workflow_type and ground_truth inputs" do
        subject
        expect(SfnGenericDispatchService).to have_received(:call).with(
          an_instance_of(BenchmarkWorkflowRun),
          hash_including(
            inputs_json: hash_including(
              workflow_type: WorkflowRun::WORKFLOW[:consensus_genome],
              ground_truth: "s3://truth/ground_truth.tsv"
            ),
            output_prefix: fake_output_prefix,
            wdl_file_name: WorkflowRun::DEFAULT_WDL_FILE_NAME,
            version: fake_benchmark_version
          )
        )
      end

      it "updates the workflow_run to running with the execution arn" do
        subject
        workflow_run.reload
        expect(workflow_run.status).to eq(WorkflowRun::STATUS[:running])
        expect(workflow_run.sfn_execution_arn).to eq(CommonStubConstants::FAKE_SFN_EXECUTION_ARN)
        expect(workflow_run.executed_at).to be_present
      end
    end

    context "for an mngs benchmark (gathers per-run output files from S3)" do
      let(:pipeline_run) { create(:pipeline_run, sample: sample, wdl_version: "7.0.0") }
      let(:workflow_run) do
        build_benchmark_run(
          "workflow_benchmarked" => short_read_workflow,
          "ground_truth_file" => "s3://truth/ground_truth.tsv",
          "run_ids" => [pipeline_run.id]
        )
      end

      let(:stage_output_json) do
        {
          SfnBenchmarkPipelineDispatchService::SHORT_READ_MNGS_MAP["taxon_counts"] => "s3://out/taxon_counts.json",
          SfnBenchmarkPipelineDispatchService::SHORT_READ_MNGS_MAP["contigs_fasta"] => "s3://out/contigs.fasta",
          SfnBenchmarkPipelineDispatchService::SHORT_READ_MNGS_MAP["contigs_summary"] => "s3://out/contig_summary.json",
        }.to_json
      end

      before do
        allow_any_instance_of(PipelineRun).to receive(:sfn_results_path).and_return("s3://results/path")
        allow(S3Util).to receive(:get_s3_file).and_return(stage_output_json)
      end

      subject { SfnBenchmarkPipelineDispatchService.call(workflow_run) }

      it "includes the per-run output file inputs keyed by run number" do
        subject
        expect(SfnGenericDispatchService).to have_received(:call).with(
          an_instance_of(BenchmarkWorkflowRun),
          hash_including(
            inputs_json: hash_including(
              :"taxon_counts_run_1" => "s3://out/taxon_counts.json",
              :"contig_fasta_run_1" => "s3://out/contigs.fasta",
              :"contig_summary_run_1" => "s3://out/contig_summary.json"
            )
          )
        )
      end
    end

    context "when the benchmark WDL version is missing" do
      let(:workflow_run) do
        build_benchmark_run(
          "workflow_benchmarked" => WorkflowRun::WORKFLOW[:consensus_genome],
          "run_ids" => []
        )
      end

      before do
        allow(AppConfigHelper).to receive(:get_workflow_version)
          .with(benchmark_workflow).and_return(nil)
      end

      subject { SfnBenchmarkPipelineDispatchService.call(workflow_run) }

      it "marks the run failed and raises SfnVersionMissingError" do
        expect { subject }.to raise_error(SfnBenchmarkPipelineDispatchService::SfnVersionMissingError)
        expect(workflow_run.reload.status).to eq(WorkflowRun::STATUS[:failed])
      end
    end

    context "when the generic dispatch raises" do
      let(:workflow_run) do
        build_benchmark_run(
          "workflow_benchmarked" => WorkflowRun::WORKFLOW[:consensus_genome],
          "run_ids" => []
        )
      end

      before do
        allow(SfnGenericDispatchService).to receive(:call).and_raise(StandardError, "boom")
      end

      subject { SfnBenchmarkPipelineDispatchService.call(workflow_run) }

      it "logs the error, marks the run failed and re-raises" do
        expect(LogUtil).to receive(:log_error).at_least(:once)
        expect { subject }.to raise_error(StandardError, "boom")
        expect(workflow_run.reload.status).to eq(WorkflowRun::STATUS[:failed])
      end
    end
  end
end
