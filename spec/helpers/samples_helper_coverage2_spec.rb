require "rails_helper"

# Wave-1 coverage supplement for app/helpers/samples_helper.rb
# (COVERAGE-GAP-ANALYSIS-2026-07-07). Targets the previously-uncovered helper
# methods and both arms of each conditional. Branch coverage is the priority.
RSpec.describe SamplesHelper, type: :helper do
  # UserMacros#create_users is not extended for `type: :helper`, so set up users
  # inline (matching the existing spec/helpers/samples_helper_spec.rb pattern).
  before do
    @admin = create(:admin, role: 1)
    @joe = create(:joe)
  end

  describe "#get_samples_list_csv_attributes" do
    it "includes both host filtering attribute sets when versions span the boundary" do
      illumina = PipelineRun::TECHNOLOGY_INPUT[:illumina]
      # One version >= the reads_after_fastp boundary, one below it. Use the
      # constant so this stays correct if the boundary version changes.
      versions = [PipelineRunsHelper::BOWTIE2_ERCC_READS_BEFORE_QUALITY_FILTERING_PIPELINE_VERSION, "1.0"]
      attrs = helper.get_samples_list_csv_attributes(versions, illumina)
      expect(attrs).to include("reads_after_fastp")       # modern
      expect(attrs).to include("reads_after_star")        # old
      expect(attrs).to include("insert_size_median")      # illumina always
    end

    it "includes both attribute sets when pipeline_run_versions is nil (else arm)" do
      illumina = PipelineRun::TECHNOLOGY_INPUT[:illumina]
      attrs = helper.get_samples_list_csv_attributes(nil, illumina)
      expect(attrs).to include("reads_after_fastp")
      expect(attrs).to include("reads_after_star")
    end

    it "returns nanopore attributes for the nanopore technology" do
      nanopore = PipelineRun::TECHNOLOGY_INPUT[:nanopore]
      attrs = helper.get_samples_list_csv_attributes(nil, nanopore)
      expect(attrs).to include("total_bases")
      expect(attrs).not_to include("insert_size_median")
    end

    it "raises for an unknown technology (else arm)" do
      expect { helper.get_samples_list_csv_attributes(nil, "quantum") }.to raise_error(/Unknown technology/)
    end
  end

  describe "#summary_stats_hash" do
    it "rounds present stats and keeps them" do
      out = helper.summary_stats_hash(qc_percent: 12.34567, compression_ratio: 2.5678, percent_remaining: 50.98765)
      expect(out[:quality_control]).to eq(12.346)
      expect(out[:compression_ratio]).to eq(2.57)
      expect(out[:passed_filters_percent]).to eq(50.988)
    end

    it "defaults to empty strings when stats are nil (nil arms) and coerces a nil arg" do
      out = helper.summary_stats_hash(nil)
      expect(out[:quality_control]).to eq('')
      expect(out[:reads_after_star]).to eq('')
    end
  end

  describe "#ont_metric_hash" do
    it "merges pr bases with rounded qc and read-length stubs" do
      pr = { total_bases: 100, fraction_subsampled_bases: 0.5 }
      out = helper.ont_metric_hash(pr, qc_percent: 88.88888)
      expect(out[:total_bases]).to eq(100)
      expect(out[:bases_after_quality_filter_percent]).to eq(88.889)
      expect(out).to have_key(:read_length_median)
    end

    it "handles a nil summary_stats arg (nil arm)" do
      pr = { total_bases: nil }
      out = helper.ont_metric_hash(pr, nil)
      expect(out[:total_bases]).to eq('')
      expect(out[:bases_after_quality_filter_percent]).to eq('')
    end
  end

  describe "#sample_status_display_for_hidden_page" do
    let(:sample) { create(:sample, project: create(:project, users: [@joe]), user: @joe) }

    it "returns 'uploading' for a CREATED sample" do
      allow(sample).to receive(:status).and_return(Sample::STATUS_CREATED)
      expect(helper.sample_status_display_for_hidden_page(sample, nil)).to eq('uploading')
    end

    it "returns '' for a CHECKED sample with no run" do
      allow(sample).to receive(:status).and_return(Sample::STATUS_CHECKED)
      expect(helper.sample_status_display_for_hidden_page(sample, nil)).to eq('')
    end

    it "returns the downcased WorkflowRun status when run is a WorkflowRun" do
      allow(sample).to receive(:status).and_return(Sample::STATUS_CHECKED)
      wr = instance_double(WorkflowRun, status: "SUCCEEDED")
      allow(wr).to receive(:instance_of?).with(WorkflowRun).and_return(true)
      expect(helper.sample_status_display_for_hidden_page(sample, wr)).to eq("succeeded")
    end

    it "maps PipelineRun job_status through the case (complete / failed / running / else)" do
      allow(sample).to receive(:status).and_return(Sample::STATUS_CHECKED)
      {
        PipelineRun::STATUS_CHECKED => 'complete',
        PipelineRun::STATUS_FAILED => 'failed',
        PipelineRun::STATUS_RUNNING => 'running',
        "SOMETHING_ELSE" => 'initializing',
      }.each do |job_status, expected|
        pr = instance_double(PipelineRun, job_status: job_status)
        allow(pr).to receive(:instance_of?).with(WorkflowRun).and_return(false)
        allow(pr).to receive(:instance_of?).with(PipelineRun).and_return(true)
        expect(helper.sample_status_display_for_hidden_page(sample, pr)).to eq(expected)
      end
    end
  end

  describe "#get_total_runtime" do
    it "returns time_to_finalized for a finalized run" do
      pr = instance_double(PipelineRun, finalized?: true, time_to_finalized: 123)
      expect(helper.get_total_runtime(pr)).to eq(123)
    end

    it "returns elapsed wall-clock time for an in-progress run (else arm)" do
      pr = instance_double(PipelineRun, finalized?: false, created_at: 10.seconds.ago)
      expect(helper.get_total_runtime(pr)).to be > 0
    end
  end

  describe "#pipeline_run_info" do
    it "builds the full hash when a pipeline_run is present" do
      pr = instance_double(
        PipelineRun, id: 7, assembly?: true, finalized: 1, created_at: Time.current,
                     status_display: "COMPLETE", alignment_config: instance_double("AlignmentConfig", name: "ncbi")
      )
      allow(helper).to receive(:get_total_runtime).with(pr).and_return(5)
      out = helper.pipeline_run_info(pr, [7], {})
      expect(out[:with_assembly]).to eq(1)
      expect(out[:report_ready]).to be(true)
      expect(out[:ncbi_index_version]).to eq("ncbi")
    end

    it "returns the QUEUED default hash when pipeline_run is nil (else arm)" do
      out = helper.pipeline_run_info(nil, [], {})
      expect(out[:result_status_description]).to eq('QUEUED FOR PROCESSING')
      expect(out[:finalized]).to eq(0)
    end

    it "reports report_ready false when the id is not in the ready set" do
      pr = instance_double(
        PipelineRun, id: 9, assembly?: false, finalized: 0, created_at: Time.current,
                     status_display: "RUNNING", alignment_config: nil
      )
      allow(helper).to receive(:get_total_runtime).and_return(1)
      out = helper.pipeline_run_info(pr, [1, 2], {})
      expect(out[:with_assembly]).to eq(0)
      expect(out[:report_ready]).to be(false)
    end
  end

  describe "#sample_uploader" do
    it "returns the uploader name + id when the sample has a user" do
      user = create(:user, name: "Uma")
      sample = create(:sample, user: user, project: create(:project, users: [user]))
      out = helper.sample_uploader(sample)
      expect(out[:name]).to eq("Uma")
      expect(out[:id]).to eq(user.id)
    end

    it "returns nil name/id when the sample has no user (nil arms)" do
      sample = create(:sample, project: create(:project, users: [@joe]), user: @joe)
      allow(sample).to receive(:user).and_return(nil)
      out = helper.sample_uploader(sample)
      expect(out[:name]).to be_nil
      expect(out[:id]).to be_nil
    end
  end

  describe "#sample_derived_data" do
    let(:sample) { create(:sample, project: create(:project, users: [@joe], name: "P"), user: @joe, host_genome: create(:host_genome, name: "HG")) }

    it "computes summary_stats when job_stats_hash present" do
      pr = instance_double(PipelineRun)
      allow(helper).to receive(:get_summary_stats).and_return({ x: 1 })
      out = helper.sample_derived_data(sample, pr, { "star_out" => {} })
      expect(out[:summary_stats]).to eq({ x: 1 })
      expect(out[:host_genome_name]).to eq("HG")
      expect(out[:project_name]).to eq("P")
    end

    it "sets summary_stats to nil when job_stats_hash is blank (else arm)" do
      out = helper.sample_derived_data(sample, nil, {})
      expect(out[:summary_stats]).to be_nil
    end
  end

  describe "#get_result_status_description_for_errored_sample" do
    def errored(err)
      s = create(:sample, project: create(:project, users: [@joe]), user: @joe)
      allow(s).to receive(:upload_error).and_return(err)
      s
    end

    it "returns SKIPPED for DO_NOT_PROCESS" do
      expect(helper.get_result_status_description_for_errored_sample(errored(Sample::DO_NOT_PROCESS))).to eq(result_status_description: 'SKIPPED')
    end

    it "returns FAILED for a generic upload error" do
      expect(helper.get_result_status_description_for_errored_sample(errored(Sample::UPLOAD_ERROR_S3_UPLOAD_FAILED))).to eq(result_status_description: 'FAILED')
    end

    it "returns INCOMPLETE for a stalled local upload (else arm)" do
      expect(helper.get_result_status_description_for_errored_sample(errored(Sample::UPLOAD_ERROR_LOCAL_UPLOAD_STALLED))).to eq(result_status_description: 'INCOMPLETE')
    end
  end

  describe "#filter_by_visibility (private)" do
    let(:samples) { Sample.all }

    it "returns public_samples when only 'public' requested (XOR true, public arm)" do
      expect(samples).to receive(:public_samples).and_return(:public_scope)
      expect(helper.send(:filter_by_visibility, samples, ["public"])).to eq(:public_scope)
    end

    it "returns private_samples when only 'private' requested (XOR true, private arm)" do
      expect(samples).to receive(:private_samples).and_return(:private_scope)
      expect(helper.send(:filter_by_visibility, samples, ["private"])).to eq(:private_scope)
    end

    it "returns the samples unchanged when both public and private requested (XOR false)" do
      expect(helper.send(:filter_by_visibility, samples, ["public", "private"])).to eq(samples)
    end

    it "returns the samples unchanged when visibility is nil (guard arm)" do
      expect(helper.send(:filter_by_visibility, samples, nil)).to eq(samples)
    end
  end

  describe "#filter_by_host (private)" do
    it "returns a false scope when query is ['none']" do
      result = helper.send(:filter_by_host, Sample.all, ["none"])
      expect(result.to_a).to eq([])
    end

    it "filters by host_genome_id otherwise" do
      hg = create(:host_genome)
      sample = create(:sample, host_genome: hg, project: create(:project, users: [@joe]), user: @joe)
      result = helper.send(:filter_by_host, Sample.all, [hg.id])
      expect(result).to include(sample)
    end
  end

  describe "#filter_by_sample_ids (private)" do
    let!(:sample) { create(:sample, project: create(:project, users: [@joe]), user: @joe) }

    it "accepts an Array of ids directly" do
      expect(helper.send(:filter_by_sample_ids, Sample.all, [sample.id])).to include(sample)
    end

    it "parses a JSON string of ids (else arm)" do
      expect(helper.send(:filter_by_sample_ids, Sample.all, "[#{sample.id}]")).to include(sample)
    end
  end

  describe "#filter_by_time (private)" do
    it "filters samples by created_at range" do
      sample = create(:sample, project: create(:project, users: [@joe]), user: @joe)
      result = helper.send(:filter_by_time, Sample.all, Date.current - 1, Date.current + 1)
      expect(result).to include(sample)
    end
  end

  describe "#validate_threshold_filter_input (private)" do
    it "passes for valid filters" do
      # Build a genuinely valid filter from the real allow-lists (the constants
      # are frozen, so they cannot be stubbed).
      valid = [{ count_type: "NT", metric: "rpm", operator: ">=", value: "1" }]
      expect { helper.send(:validate_threshold_filter_input, valid, ["species"]) }.not_to raise_error
    end

    it "raises for an invalid metric" do
      invalid = [{ count_type: "NT", metric: "bogus_metric", operator: ">=", value: "1" }]
      expect { helper.send(:validate_threshold_filter_input, invalid, ["species"]) }.to raise_error(StandardError)
    end
  end

  describe "#samples_by_domain" do
    before do
      @project = create(:project, users: [@joe])
      @cp = Power.new(@joe)
      # current_power is a controller concern, not defined on the ActionView
      # helper object, so bypass verifying-double checks to stub it.
      without_partial_double_verification do
        allow(helper).to receive(:current_power).and_return(@cp)
      end
    end

    it "returns my_data_samples for 'my_data'" do
      expect(@cp).to receive(:my_data_samples).and_return(:my_data)
      expect(helper.samples_by_domain("my_data")).to eq(:my_data)
    end

    it "returns public_samples for 'public'" do
      expect(Sample).to receive(:public_samples).and_return(:public)
      expect(helper.samples_by_domain("public")).to eq(:public)
    end

    it "returns current_power.samples for any other domain (else arm)" do
      expect(@cp).to receive(:samples).and_return(:all)
      expect(helper.samples_by_domain("all_data")).to eq(:all)
    end
  end

  describe "#samples_by_domain_with_current_power" do
    let(:cp) { instance_double(Power) }

    it "returns my_data_samples for 'my_data'" do
      expect(cp).to receive(:my_data_samples).and_return(:md)
      expect(helper.samples_by_domain_with_current_power("my_data", cp)).to eq(:md)
    end

    it "returns Sample.public_samples for 'public'" do
      allow(Sample).to receive(:public_samples).and_return(:pub)
      expect(helper.samples_by_domain_with_current_power("public", cp)).to eq(:pub)
    end

    it "returns cp.samples for the else arm" do
      expect(cp).to receive(:samples).and_return(:all)
      expect(helper.samples_by_domain_with_current_power("other", cp)).to eq(:all)
    end
  end

  describe "#increment_sample_name" do
    it "returns the name unchanged when no collision" do
      expect(helper.increment_sample_name("s", ["other"])).to eq("s")
    end

    it "appends a suffix until it is unique" do
      # The method appends to the growing name each iteration ("s" -> "s_1" ->
      # "s_1_2"), so a collision on the first suffix yields "s_1_2".
      expect(helper.increment_sample_name("s", ["s", "s_1"])).to eq("s_1_2")
    end
  end

  describe ".get_sample_count_from_sample_paths" do
    it "counts distinct sample ids parsed from s3 paths" do
      urls = [
        "s3://idseq-samples-prod/samples/1/10/fastqs/a.fastq",
        "s3://idseq-samples-prod/samples/1/10/results/b.fasta",
        "s3://idseq-samples-prod/samples/2/20/fastqs/c.fastq",
        "s3://not-a-sample-path/x",
      ]
      expect(SamplesHelper.get_sample_count_from_sample_paths(urls)).to eq(2)
    end
  end

  describe "#bulk_create_and_dispatch_workflow_runs" do
    it "raises WorkflowNotFoundError for an unknown workflow" do
      expect { helper.bulk_create_and_dispatch_workflow_runs([], "not-a-workflow", @joe) }
        .to raise_error(SamplesHelper::WorkflowNotFoundError)
    end

    it "returns [] when there are no eligible sample ids (empty filtered arm)" do
      expect(helper.bulk_create_and_dispatch_workflow_runs([], WorkflowRun::WORKFLOW[:amr], @joe)).to eq([])
    end
  end

  describe "#parsed_samples_for_s3_path" do
    it "returns nil for a non-s3 scheme (scheme guard)" do
      expect(helper.parsed_samples_for_s3_path("https://example.com/x", 1, 1)).to be_nil
    end

    it "returns an empty list when the bucket host is empty" do
      # An empty host is "" (not nil), so the nil-guard does not trip; the empty
      # bucket simply yields no matching sample files.
      expect(helper.parsed_samples_for_s3_path("s3:///no-bucket", 1, 1)).to eq([])
    end
  end

  describe ".samples_by_metadata_field" do
    it "groups on the validated field for a non-location field" do
      mf = create(:metadata_field, name: "sample_type", base_type: MetadataField::STRING_TYPE)
      sample = create(:sample, project: create(:project, users: [@joe]), user: @joe, metadata_fields: { "sample_type" => "CSF" })
      # The method returns a grouped relation; every caller consumes it with
      # .count (loading full rows via .to_a violates MySQL only_full_group_by).
      result = SamplesHelper.samples_by_metadata_field([sample.id], "sample_type").count
      expect(result).to be_present
    end
  end
end
