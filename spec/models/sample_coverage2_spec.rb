require 'rails_helper'

# Wave-1 coverage supplement for app/models/sample.rb (COVERAGE-GAP-ANALYSIS-2026-07-07).
# Complements spec/models/sample_spec.rb and spec/models/sample_coverage_spec.rb by
# targeting the previously-uncovered methods and, crucially, BOTH arms of each
# conditional (branch coverage is the priority). No app code is changed here.
RSpec.describe Sample, type: :model do
  create_users

  let(:project) { create(:project, users: [@joe]) }

  def sample_with(**attrs)
    create(:sample, project: project, user: @joe, **attrs)
  end

  describe "#skip_deutero_filter_flag" do
    it "returns 0 when host_genome present and skip_deutero_filter is 0" do
      hg = create(:host_genome, skip_deutero_filter: 0)
      sample = sample_with(host_genome: hg)
      expect(sample.skip_deutero_filter_flag).to eq(0)
    end

    it "returns 1 when host_genome present and skip_deutero_filter is 1" do
      hg = create(:host_genome, skip_deutero_filter: 1)
      sample = sample_with(host_genome: hg)
      expect(sample.skip_deutero_filter_flag).to eq(1)
    end

    it "returns 1 when host_genome is nil (the !host_genome arm)" do
      sample = sample_with
      allow(sample).to receive(:host_genome).and_return(nil)
      expect(sample.skip_deutero_filter_flag).to eq(1)
    end
  end

  describe "#host_genome_name" do
    it "returns the host genome name when present" do
      hg = create(:host_genome, name: "Mosquito")
      sample = sample_with(host_genome: hg)
      expect(sample.host_genome_name).to eq("Mosquito")
    end

    it "returns nil when host_genome is nil" do
      sample = sample_with
      allow(sample).to receive(:host_genome).and_return(nil)
      expect(sample.host_genome_name).to be_nil
    end
  end

  describe "#uploaded_from_basespace?" do
    it "is true when uploaded_from_basespace == 1" do
      expect(sample_with(uploaded_from_basespace: 1).uploaded_from_basespace?).to be(true)
    end

    it "is false when uploaded_from_basespace == 0" do
      expect(sample_with(uploaded_from_basespace: 0).uploaded_from_basespace?).to be(false)
    end
  end

  describe "#input_file_s3_paths" do
    it "returns all input file s3 paths when no file_type is given" do
      sample = sample_with
      expect(sample.input_file_s3_paths).to all(be_a(String))
      expect(sample.input_file_s3_paths.length).to eq(sample.input_files.length)
    end

    it "restricts to the given file_type (by_type branch)" do
      sample = sample_with
      paths = sample.input_file_s3_paths(InputFile::FILE_TYPE_FASTQ)
      expect(paths.length).to eq(sample.input_files.by_type(InputFile::FILE_TYPE_FASTQ).length)
    end
  end

  describe "#default_background_id" do
    it "uses the host genome's default_background_id when present" do
      hg = create(:host_genome, default_background_id: 42)
      sample = sample_with(host_genome: hg)
      expect(sample.default_background_id).to eq(42)
    end

    it "falls back to the Human host genome default when host has none" do
      create(:host_genome, name: "Human", default_background_id: 7)
      hg = create(:host_genome, default_background_id: nil)
      sample = sample_with(host_genome: hg)
      expect(sample.default_background_id).to eq(7)
    end
  end

  describe "#pipeline_run_by_version" do
    it "returns a run with taxon_counts when one exists" do
      sample = sample_with
      pr = create(:pipeline_run, sample: sample, pipeline_version: "3.0")
      create(:taxon_count, pipeline_run: pr) # no taxon_name -> no TaxonLineage lookup
      expect(sample.pipeline_run_by_version("3.0")).to eq(pr)
    end

    it "returns the first run when none have taxon_counts" do
      sample = sample_with
      pr = create(:pipeline_run, sample: sample, pipeline_version: "3.0")
      expect(sample.pipeline_run_by_version("3.0")).to eq(pr)
    end

    it "queries for nil pipeline_version via the PIPELINE_VERSION_WHEN_NULL branch" do
      sample = sample_with
      pr = create(:pipeline_run, sample: sample, pipeline_version: nil)
      expect(sample.pipeline_run_by_version(PipelineRun::PIPELINE_VERSION_WHEN_NULL)).to eq(pr)
    end
  end

  describe "#fasta_input?" do
    it "is true for a fasta first input file" do
      sample = sample_with
      allow(sample.input_files[0]).to receive(:file_extension).and_return("fasta")
      expect(sample.fasta_input?).to be(true)
    end

    it "is false for a fastq first input file" do
      sample = sample_with
      allow(sample.input_files[0]).to receive(:file_extension).and_return("fastq")
      expect(sample.fasta_input?).to be(false)
    end
  end

  describe ".search" do
    it "returns the scoped relation when search is falsy" do
      sample_with(name: "alpha")
      expect(Sample.search(nil)).to eq(Sample.all)
    end

    it "matches by name when a search string is given (no eligible_pr_ids)" do
      match = sample_with(name: "findme")
      sample_with(name: "other")
      expect(Sample.search("findme")).to include(match)
    end
  end

  describe ".search_by_name" do
    it "returns scoped when query is nil" do
      sample_with(name: "abc")
      expect(Sample.search_by_name(nil).to_a).to eq(Sample.all.to_a)
    end

    it "matches all tokens in the query" do
      match = sample_with(name: "human lung sample")
      sample_with(name: "mouse liver")
      expect(Sample.search_by_name("human lung")).to include(match)
    end
  end

  describe "#get_existing_metadatum" do
    it "finds an existing metadatum by field name" do
      sample = sample_with(metadata_fields: { "sample_type" => "CSF" })
      expect(sample.get_existing_metadatum("sample_type")).to be_present
    end

    it "returns nil when no metadatum matches the key" do
      sample = sample_with
      expect(sample.get_existing_metadatum("nonexistent_field")).to be_nil
    end
  end

  describe "#metadatum_add_or_update" do
    # Attach a metadata field of the given base_type to both the sample's project
    # and its host genome so get_available_matching_field finds it.
    def sample_with_field(base_type)
      hg = create(:host_genome)
      sample = sample_with(host_genome: hg)
      field = create(:metadata_field, name: "cov2_field", base_type: base_type)
      sample.project.metadata_fields << field
      hg.metadata_fields << field
      sample
    end

    it "returns ok and persists a valid string field value" do
      sample = sample_with_field(MetadataField::STRING_TYPE)
      result = sample.metadatum_add_or_update("cov2_field", "some text")
      expect(result[:status]).to eq("ok")
      expect(sample.get_existing_metadatum("cov2_field")).to be_present
    end

    it "returns ok status with a blank value (no-op create branch)" do
      sample = sample_with_field(MetadataField::STRING_TYPE)
      result = sample.metadatum_add_or_update("cov2_field", "")
      expect(result[:status]).to eq("ok")
    end

    it "returns error when the metadatum fails validation (numeric field, non-numeric value)" do
      sample = sample_with_field(MetadataField::NUMBER_TYPE)
      result = sample.metadatum_add_or_update("cov2_field", "not-a-number")
      expect(result[:status]).to eq("error")
      expect(result[:error]).to be_present
    end
  end

  describe "#metadata_fields_info" do
    it "returns the intersection of project and host genome field info" do
      mf = create(:metadata_field, name: "sample_type")
      project.metadata_fields << mf
      hg = create(:host_genome)
      hg.metadata_fields << mf
      sample = sample_with(host_genome: hg)
      infos = sample.metadata_fields_info
      expect(infos.map { |i| i[:key] }).to include("sample_type")
    end
  end

  describe "#metadata_with_base_type" do
    it "augments each metadatum with a stringified base_type" do
      sample = sample_with(metadata_fields: { "sample_type" => "CSF" })
      result = sample.metadata_with_base_type
      expect(result).to be_an(Array)
      expect(result.first["base_type"]).to be_present
    end
  end

  describe "#as_json" do
    it "defaults :methods to include host_genome_name and private_until" do
      sample = sample_with
      json = sample.as_json
      expect(json).to have_key("host_genome_name")
      expect(json).to have_key("private_until")
    end

    it "respects an explicitly-passed :methods option" do
      sample = sample_with
      json = sample.as_json(methods: [:sample_path])
      expect(json).to have_key("sample_path")
    end
  end

  describe "#kickoff_pipeline (short-read mNGS)" do
    it "sets DO_NOT_PROCESS and does not create a run when do_not_process is set" do
      sample = sample_with
      sample.update_column(:do_not_process, true)
      allow(sample.pipeline_runs).to receive(:in_progress).and_return(PipelineRun.none)
      expect { sample.kickoff_pipeline }.not_to change { sample.pipeline_runs.count }
      expect(sample.reload.upload_error).to eq(Sample::DO_NOT_PROCESS)
    end

    it "returns early without creating a run when a pipeline run is in progress" do
      sample = sample_with
      # Simulate an in-progress run so the guard clause returns early.
      allow(sample.pipeline_runs).to receive(:in_progress).and_return(sample.pipeline_runs.where("1=1"))
      allow(sample.pipeline_runs.in_progress).to receive(:empty?).and_return(false)
      expect(PipelineRun).not_to receive(:new)
      sample.kickoff_pipeline
    end

    it "logs an error and sets UPLOAD_ERROR_PIPELINE_KICKOFF when saving the run raises" do
      sample = sample_with
      allow(sample.pipeline_runs).to receive(:in_progress).and_return(PipelineRun.none)
      allow(Sample).to receive(:pipeline_commit).and_return("abc123")
      allow_any_instance_of(PipelineRun).to receive(:save!).and_raise(StandardError.new("boom"))
      expect(LogUtil).to receive(:log_error).at_least(:once)
      sample.kickoff_pipeline
      expect(sample.reload.upload_error).to eq(Sample::UPLOAD_ERROR_PIPELINE_KICKOFF)
    end
  end

  describe "#check_status (before_save hook)" do
    it "no-ops for a CREATED sample (guard clause arm)" do
      sample = sample_with(status: Sample::STATUS_CREATED)
      expect(sample.send(:check_status)).to be_nil
    end
  end

  describe ".pipeline_commit" do
    it "returns false when the git ls-remote output is blank" do
      allow(Syscall).to receive(:pipe_with_output).and_return("")
      expect(Sample.pipeline_commit("missing-branch")).to be(false)
    end

    it "returns the sha (first token) when the branch is found" do
      allow(Syscall).to receive(:pipe_with_output).and_return("deadbeef\trefs/heads/main")
      expect(Sample.pipeline_commit("main")).to eq("deadbeef")
    end
  end

  describe "#initiate_input_file_upload" do
    it "enqueues TransferBasespaceFiles for a basespace upload" do
      sample = sample_with
      allow(sample).to receive(:uploaded_from_basespace?).and_return(true)
      expect(Resque).to receive(:enqueue).with(TransferBasespaceFiles, sample.id, anything, anything)
      sample.initiate_input_file_upload
    end

    it "enqueues InitiateS3Cp for an S3 first input file" do
      sample = sample_with
      allow(sample).to receive(:uploaded_from_basespace?).and_return(false)
      allow(sample.input_files.first).to receive(:source_type).and_return(InputFile::SOURCE_TYPE_S3)
      expect(Resque).to receive(:enqueue).with(InitiateS3Cp, sample.id)
      sample.initiate_input_file_upload
    end

    it "does nothing when not basespace and not an S3 source (neither arm)" do
      sample = sample_with
      allow(sample).to receive(:uploaded_from_basespace?).and_return(false)
      allow(sample.input_files.first).to receive(:source_type).and_return(InputFile::SOURCE_TYPE_LOCAL)
      expect(Resque).not_to receive(:enqueue)
      sample.initiate_input_file_upload
    end
  end

  describe "#move_to_project" do
    it "moves S3 data and updates the project_id" do
      sample = sample_with
      new_project = create(:project, users: [@joe])
      allow(Syscall).to receive(:s3_mv_recursive).and_return(true)
      sample.move_to_project(new_project.id)
      expect(sample.reload.project_id).to eq(new_project.id)
    end
  end

  describe "#results_folder_files" do
    it "lists sample output when there is no pipeline run" do
      sample = sample_with
      allow(sample).to receive(:list_outputs).and_return([{ key: "k" }])
      expect(sample.results_folder_files).to eq([{ key: "k" }])
    end

    it "uses sfn_results_path for a step-function run (>= v2, step_function? true)" do
      sample = sample_with
      pr = create(:pipeline_run, sample: sample, pipeline_version: "5.0")
      allow(sample).to receive(:first_pipeline_run).and_return(pr)
      allow(sample).to receive(:pipeline_version_at_least_2).and_return(true)
      allow(pr).to receive(:step_function?).and_return(true)
      allow(pr).to receive(:sfn_results_path).and_return("s3://bucket/sfn")
      allow(sample).to receive(:list_outputs).with("s3://bucket/sfn").and_return([:sfn])
      expect(sample.results_folder_files).to eq([:sfn])
    end

    it "assembles the legacy (< v2) stage1 + stage2 file lists" do
      sample = sample_with
      pr = create(:pipeline_run, sample: sample, pipeline_version: "1.0")
      allow(sample).to receive(:first_pipeline_run).and_return(pr)
      allow(sample).to receive(:pipeline_version_at_least_2).and_return(false)
      allow(pr).to receive(:host_filter_output_s3_path).and_return("s3://b/host")
      allow(pr).to receive(:alignment_output_s3_path).and_return("s3://b/align")
      allow(sample).to receive(:list_outputs).with("s3://b/host").and_return([:s1])
      allow(sample).to receive(:list_outputs).with("s3://b/align", 2).and_return([:s2])
      expect(sample.results_folder_files).to eq([:s1, :s2])
    end
  end

  describe ".sort_samples scopes (SQL execution)" do
    before do
      @s1 = sample_with(name: "b-sample")
      @s2 = sample_with(name: "a-sample")
    end

    it "sorts by host genome name" do
      expect(Sample.where(id: [@s1.id, @s2.id]).sort_by_host_genome("asc")).to be_present
    end

    it "sorts by pipeline run metric" do
      create(:pipeline_run, sample: @s1, total_reads: 10)
      create(:pipeline_run, sample: @s2, total_reads: 20)
      result = Sample.where(id: [@s1.id, @s2.id]).sort_by_pipeline_run("total_reads", "desc")
      expect(result.to_a).to be_present
    end

    it "sorts by insert size" do
      expect(Sample.where(id: [@s1.id, @s2.id]).sort_by_insert_size("asc")).to be_present
    end

    it "sorts by metadata field" do
      expect(Sample.where(id: [@s1.id, @s2.id]).sort_by_metadata("sample_type", "asc")).to be_present
    end

    it "sorts by location" do
      expect(Sample.where(id: [@s1.id, @s2.id]).sort_by_location("asc")).to be_present
    end
  end

  describe ".sort_samples dispatcher" do
    let(:relation) { Sample.where(id: [sample_with.id]) }

    it "routes 'sample' (name) sort key to a samples.name order" do
      expect(Sample.sort_samples(relation, "sample", "asc")).to be_present
    end

    it "routes 'host' to sort_by_host_genome" do
      expect(relation).to receive(:sort_by_host_genome).with("asc").and_return(relation)
      Sample.sort_samples(relation, "host", "asc")
    end

    it "routes a pipeline-run key to sort_by_pipeline_run" do
      expect(relation).to receive(:sort_by_pipeline_run).and_return(relation)
      Sample.sort_samples(relation, "totalReads", "desc")
    end

    it "routes 'meanInsertSize' to sort_by_insert_size" do
      expect(relation).to receive(:sort_by_insert_size).and_return(relation)
      Sample.sort_samples(relation, "meanInsertSize", "asc")
    end

    it "returns the relation unchanged for an unknown sort key (else arm)" do
      expect(Sample.sort_samples(relation, "totally_unknown_key", "asc")).to eq(relation)
    end
  end

  describe ".by_pipeline_result_status" do
    it "filters samples joined to non-deprecated pipeline runs by results_finalized" do
      sample = sample_with
      create(:pipeline_run, sample: sample, deprecated: false, results_finalized: PipelineRun::FINALIZED_SUCCESS)
      expect(Sample.by_pipeline_result_status(results_finalized: PipelineRun::FINALIZED_SUCCESS)).to include(sample)
    end
  end

  describe ".group_taxon_count_filters_by_count_type" do
    it "groups >= and <= filter statements by uppercased count type" do
      filters = [
        { count_type: "nt", metric: "count", operator: ">=", value: "5" },
        { count_type: "nt", metric: "count", operator: "<=", value: "50" },
        { count_type: "nr", metric: "count", operator: ">=", value: "1" },
      ]
      result = Sample.group_taxon_count_filters_by_count_type(filters)
      expect(result.keys).to contain_exactly("NT", "NR")
      expect(result["NT"].length).to eq(2)
    end
  end
end
