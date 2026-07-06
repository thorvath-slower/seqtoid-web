require "rails_helper"

# Coverage Wave 5: exercises the ONT single-stage pipeline viz builder end to end.
# External systems are stubbed at the seams: retrieve_wdl (S3), parse_wdl (Open3
# shelling out to the python WDL parser), the S3 status2.json fetch, and the
# sample's results_folder_files listing. This lets us feed canned-but-representative
# WDL info + result files and assert the parsed graph structure across real branches.
RSpec.describe SfnSingleStagePipelineDataService do
  let(:nanopore) { PipelineRun::TECHNOLOGY_INPUT[:nanopore] }
  let(:project) { create(:public_project) }
  let(:sample) { create(:sample, project: project, status: Sample::STATUS_CHECKED) }
  let(:pipeline_run) do
    create(:pipeline_run,
           sample: sample,
           technology: nanopore,
           wdl_version: "1.0",
           pipeline_version: "1.0",
           sfn_execution_arn: "fake:sfn:arn")
  end

  # A minimal but representative parsed ONT WDL: two tasks, one workflow input,
  # one file flowing from RunValidateInput -> RunQualityFilter.
  let(:wdl_info) do
    {
      "inputs" => { "input_fastq" => "File", "docker_image_id" => "String" },
      "task_names" => %w[RunValidateInput RunQualityFilter],
      "task_inputs" => {
        "RunValidateInput" => ["WorkflowInput.input_fastq", "WorkflowInput.docker_image_id"],
        "RunQualityFilter" => ["RunValidateInput.validated_fastq", "WorkflowInput.docker_image_id"],
      },
      "basenames" => {
        "RunValidateInput.validated_fastq" => "validated.fastq",
        "RunQualityFilter.quality_filtered_fastq" => "quality_filtered.fastq",
      },
      "outputs" => {},
    }
  end

  # Simulates the status2.json emitted by the pipeline.
  let(:step_statuses) do
    {
      "RunValidateInput" => {
        "status" => "uploaded",
        "start_time" => "1670355490.14",
        "end_time" => "1670355519.62",
      },
      "RunQualityFilter" => {
        "status" => "running",
      },
    }
  end

  # Result files as returned by sample.results_folder_files.
  let(:result_files) do
    [
      { display_name: "validated.fastq", url: "s3://bucket/validated.fastq", size: 100, key: "prefix/validated.fastq" },
      { display_name: "quality_filtered.fastq", url: "s3://bucket/quality_filtered.fastq", size: 200, key: "prefix/quality_filtered.fastq" },
    ]
  end

  before do
    allow_any_instance_of(described_class).to receive(:retrieve_wdl).and_return("raw wdl text")
    allow_any_instance_of(described_class).to receive(:parse_wdl).and_return(wdl_info)
    allow_any_instance_of(described_class).to receive(:single_stage_pipeline_step_statuses).and_return(step_statuses)
    allow_any_instance_of(Sample).to receive(:results_folder_files).and_return(result_files)
  end

  describe "#call" do
    subject { described_class.call(pipeline_run.id, nanopore, false) }

    it "returns a single-stage structure with the expected top-level keys" do
      expect(subject.keys).to contain_exactly(:stages, :edges, :status)
    end

    it "wraps the steps in a single ONT stage" do
      stages = subject[:stages]
      expect(stages.length).to eq(1)
      expect(stages[0][:name]).to eq("ONT mNGS Pipeline")
      expect(stages[0][:steps].map { |s| s[:name] }).to eq(%w[RunValidateInput RunQualityFilter])
    end

    it "maps step statuses to viz statuses" do
      steps = subject[:stages][0][:steps]
      expect(steps[0][:status]).to eq("finished")   # uploaded -> finished
      expect(steps[1][:status]).to eq("inProgress") # running -> inProgress
    end

    it "attaches the canned step descriptions" do
      steps = subject[:stages][0][:steps]
      expect(steps[0][:description]).to eq("Validates input files are FASTQ format")
    end

    it "attaches output files to their producing step" do
      steps = subject[:stages][0][:steps]
      output_names = steps[0][:outputFiles].map { |f| f[:displayName] }
      expect(output_names).to include("validated.fastq")
    end

    it "builds edges between steps and populates node edge indices" do
      edges = subject[:edges]
      expect(edges).not_to be_empty
      steps = subject[:stages][0][:steps]
      # RunValidateInput produces a file consumed by RunQualityFilter, so it must have an output edge.
      expect(steps[0][:outputEdges]).not_to be_empty
      expect(steps[1][:inputEdges]).not_to be_empty
    end

    it "computes the overall pipeline status as inProgress" do
      expect(subject[:status]).to eq("inProgress")
    end
  end

  describe "host filtering url redaction" do
    it "nils out download urls for pre-filtered steps when remove_host_filtering_urls is true" do
      result = described_class.call(pipeline_run.id, nanopore, true)
      steps = result[:stages][0][:steps]
      validate_step = steps.detect { |s| s[:name] == "RunValidateInput" }
      # RunValidateInput is a PRE_FILTERED_STEP; its output file urls should be redacted.
      validate_step[:outputFiles].each do |file|
        expect(file[:url]).to be_nil
      end
    end

    it "keeps download urls when remove_host_filtering_urls is false" do
      result = described_class.call(pipeline_run.id, nanopore, false)
      steps = result[:stages][0][:steps]
      validate_step = steps.detect { |s| s[:name] == "RunValidateInput" }
      urls = validate_step[:outputFiles].map { |f| f[:url] }
      expect(urls).to include("s3://bucket/validated.fastq")
    end
  end

  describe "#pipeline_job_status" do
    let(:service) { described_class.allocate }

    it "prioritizes userErrored" do
      expect(service.pipeline_job_status(%w[finished userErrored pipelineErrored])).to eq("userErrored")
    end

    it "returns pipelineErrored when present without userErrored" do
      expect(service.pipeline_job_status(%w[finished pipelineErrored])).to eq("pipelineErrored")
    end

    it "returns inProgress when a step is inProgress" do
      expect(service.pipeline_job_status(%w[finished inProgress])).to eq("inProgress")
    end

    it "returns inProgress when mixing notStarted and finished" do
      expect(service.pipeline_job_status(%w[notStarted finished])).to eq("inProgress")
    end

    it "returns notStarted when only notStarted" do
      expect(service.pipeline_job_status(%w[notStarted notStarted])).to eq("notStarted")
    end

    it "returns finished when all finished" do
      expect(service.pipeline_job_status(%w[finished finished])).to eq("finished")
    end

    it "defaults to inProgress for an unexpected empty set" do
      expect(service.pipeline_job_status([])).to eq("inProgress")
    end
  end

  describe "#redefine_job_status" do
    let(:service) do
      s = described_class.allocate
      s.instance_variable_set(:@analysis_type, nanopore)
      s.instance_variable_set(:@analysis_run, pipeline_run)
      s
    end

    it "maps instantiated and nil to notStarted" do
      expect(service.redefine_job_status("instantiated")).to eq("notStarted")
      expect(service.redefine_job_status(nil)).to eq("notStarted")
    end

    it "maps uploaded to finished" do
      expect(service.redefine_job_status("uploaded")).to eq("finished")
    end

    it "maps pipeline_errored to pipelineErrored" do
      expect(service.redefine_job_status("pipeline_errored")).to eq("pipelineErrored")
    end

    it "maps errored and user_errored to userErrored" do
      expect(service.redefine_job_status("errored")).to eq("userErrored")
      expect(service.redefine_job_status("user_errored")).to eq("userErrored")
    end

    it "maps running to inProgress" do
      expect(service.redefine_job_status("running")).to eq("inProgress")
    end
  end

  describe "#update_step_keys" do
    let(:service) do
      s = described_class.allocate
      s.instance_variable_set(:@analysis_type, nanopore)
      s
    end

    it "renames pipeline output keys to WDL task names for nanopore" do
      statuses = {
        "refined_taxon_count_out" => { "status" => "uploaded" },
        "contig_summary_out" => { "status" => "uploaded" },
        "refined_taxid_locator_out" => { "status" => "uploaded" },
        "coverage_viz_out" => { "status" => "uploaded" },
      }
      result = service.update_step_keys(statuses)
      expect(result.keys).to contain_exactly("CombineTaxonCounts", "CombineJson", "GenerateTaxidLocator", "GenerateCoverageViz")
    end

    it "leaves unknown keys untouched" do
      statuses = { "SomethingElse" => { "status" => "uploaded" } }
      expect(service.update_step_keys(statuses)).to eq(statuses)
    end
  end

  describe "#get_result_file_data" do
    let(:service) do
      s = described_class.allocate
      s.instance_variable_set(:@result_files, {
                                "validated.fastq" => { displayName: "validated.fastq", url: "u" },
                              })
      s
    end

    it "returns the matching result file entry" do
      expect(service.get_result_file_data("validated.fastq")[:url]).to eq("u")
    end

    it "falls back to basename lookup" do
      expect(service.get_result_file_data("some/dir/validated.fastq")[:url]).to eq("u")
    end

    it "returns a nil-url placeholder when no result file exists" do
      data = service.get_result_file_data("missing.fastq")
      expect(data).to eq(displayName: "missing.fastq", url: nil)
    end
  end
end
