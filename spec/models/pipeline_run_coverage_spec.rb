require "rails_helper"

# Coverage Wave 4a: broad coverage of PipelineRun's public methods, predicates,
# scopes, state/status derivation, path derivations, and numeric helpers.
# Kept in a dedicated file to avoid churn in the existing pipeline_run_spec.rb.
describe PipelineRun, type: :model do
  create_users

  let(:project) { create(:project, users: [@joe], name: "Cov Project") }
  let(:sample) { create(:sample, project: project, user: @joe, name: "cov_sample") }

  before do
    @mock_aws_clients = {
      s3: Aws::S3::Client.new(stub_responses: true),
      states: Aws::States::Client.new(stub_responses: true),
    }
    allow(AwsClient).to receive(:[]) { |client| @mock_aws_clients[client] }
  end

  describe "validations" do
    it "requires a valid technology" do
      pr = build(:pipeline_run, sample: sample, technology: "Nonsense")
      expect(pr).not_to be_valid
      expect(pr.errors[:technology]).to be_present
    end

    it "rejects an out-of-range results_finalized value" do
      pr = build(:pipeline_run, sample: sample, results_finalized: 999)
      expect(pr).not_to be_valid
      expect(pr.errors[:results_finalized]).to be_present
    end

    it "rejects a finalized value not in [0, 1]" do
      pr = build(:pipeline_run, sample: sample, finalized: 5)
      expect(pr).not_to be_valid
    end

    it "rejects a negative total_ercc_reads" do
      pr = build(:pipeline_run, sample: sample, total_ercc_reads: -1)
      expect(pr).not_to be_valid
    end
  end

  describe "#workflow" do
    it "returns short_read_mngs for illumina" do
      pr = build(:pipeline_run, sample: sample, technology: PipelineRun::TECHNOLOGY_INPUT[:illumina])
      expect(pr.workflow).to eq(WorkflowRun::WORKFLOW[:short_read_mngs])
    end

    it "returns long_read_mngs for nanopore" do
      pr = build(:pipeline_run, sample: sample, technology: PipelineRun::TECHNOLOGY_INPUT[:nanopore])
      expect(pr.workflow).to eq(WorkflowRun::WORKFLOW[:long_read_mngs])
    end
  end

  describe "#parse_dag_vars" do
    it "parses stored dag_vars json" do
      pr = build(:pipeline_run, sample: sample, dag_vars: '{"a":1}')
      expect(pr.parse_dag_vars).to eq("a" => 1)
    end

    it "defaults to an empty hash when nil" do
      pr = build(:pipeline_run, sample: sample, dag_vars: nil)
      expect(pr.parse_dag_vars).to eq({})
    end
  end

  describe "#check_box_label" do
    it "includes project name, sample name, and id" do
      pr = create(:pipeline_run, sample: sample)
      expect(pr.check_box_label).to eq("Cov Project : cov_sample (#{pr.id})")
    end
  end

  describe "predicates" do
    it "#finalized? reflects the finalized column" do
      expect(build(:pipeline_run, sample: sample, finalized: 1).finalized?).to be(true)
      expect(build(:pipeline_run, sample: sample, finalized: 0).finalized?).to be(false)
    end

    it "#results_finalized? is true only for terminal values" do
      expect(build(:pipeline_run, sample: sample, results_finalized: PipelineRun::FINALIZED_SUCCESS).results_finalized?).to be(true)
      expect(build(:pipeline_run, sample: sample, results_finalized: PipelineRun::FINALIZED_FAIL).results_finalized?).to be(true)
      expect(build(:pipeline_run, sample: sample, results_finalized: PipelineRun::IN_PROGRESS).results_finalized?).to be(false)
    end

    it "#succeeded? is true when job_status is CHECKED" do
      expect(build(:pipeline_run, sample: sample, job_status: PipelineRun::STATUS_CHECKED).succeeded?).to be(true)
      expect(build(:pipeline_run, sample: sample, job_status: PipelineRun::STATUS_RUNNING).succeeded?).to be(false)
    end

    it "#ready_for_cache? requires success and CHECKED" do
      expect(build(:pipeline_run, sample: sample, results_finalized: PipelineRun::FINALIZED_SUCCESS, job_status: PipelineRun::STATUS_CHECKED).ready_for_cache?).to be(true)
      expect(build(:pipeline_run, sample: sample, results_finalized: PipelineRun::FINALIZED_SUCCESS, job_status: PipelineRun::STATUS_RUNNING).ready_for_cache?).to be(false)
      expect(build(:pipeline_run, sample: sample, results_finalized: PipelineRun::FINALIZED_FAIL, job_status: PipelineRun::STATUS_CHECKED).ready_for_cache?).to be(false)
    end

    describe "#failed?" do
      it "is truthy when job_status contains FAILED" do
        expect(build(:pipeline_run, sample: sample, job_status: "3.Post Processing-FAILED").failed?).to be_truthy
      end

      it "is truthy when results_finalized is FINALIZED_FAIL" do
        expect(build(:pipeline_run, sample: sample, job_status: PipelineRun::STATUS_RUNNING, results_finalized: PipelineRun::FINALIZED_FAIL).failed?).to be_truthy
      end

      it "is falsy for a running non-failed run" do
        expect(build(:pipeline_run, sample: sample, job_status: PipelineRun::STATUS_RUNNING, results_finalized: PipelineRun::IN_PROGRESS).failed?).to be_falsy
      end
    end

    it "#taxon_byte_ranges_available? reflects presence of byteranges" do
      pr = create(:pipeline_run, sample: sample)
      expect(pr.taxon_byte_ranges_available?).to be(false)
      # The :taxon_byterange factory defines self-referential attribute blocks
      # (e.g. `taxid { taxid }`), so every attribute MUST be passed explicitly
      # or FactoryBot recurses into a SystemStackError. This mirrors how the
      # factory is used elsewhere (see phylo_tree_ngs_controller_spec).
      create(:taxon_byterange,
             pipeline_run: pr,
             taxid: 1,
             hit_type: TaxonCount::COUNT_TYPE_NT,
             first_byte: 0,
             last_byte: 70)
      expect(pr.reload.taxon_byte_ranges_available?).to be(true)
    end
  end

  describe "#completed?" do
    it "is true when finalized" do
      pr = create(:pipeline_run, sample: sample, finalized: 1)
      expect(pr.completed?).to be(true)
    end

    it "is true for legacy runs with no stages that are CHECKED" do
      pr = create(:pipeline_run, sample: sample, finalized: 0, job_status: PipelineRun::STATUS_CHECKED,
                                 pipeline_execution_strategy: PipelineRun.pipeline_execution_strategies[:directed_acyclic_graph])
      pr.pipeline_run_stages.destroy_all
      expect(pr.reload.completed?).to be(true)
    end

    it "is falsy for an in-progress run" do
      pr = create(:pipeline_run, sample: sample, finalized: 0, job_status: PipelineRun::STATUS_RUNNING)
      expect(pr.completed?).to be_falsy
    end
  end

  describe "output-state creation callbacks" do
    it "creates output_states for illumina target outputs on create" do
      pr = create(:pipeline_run, sample: sample, technology: PipelineRun::TECHNOLOGY_INPUT[:illumina])
      expect(pr.output_states.pluck(:output)).to match_array(PipelineRun::TARGET_OUTPUTS[PipelineRun::TECHNOLOGY_INPUT[:illumina]])
      expect(pr.output_states.pluck(:state).uniq).to eq([PipelineRun::STATUS_UNKNOWN])
      expect(pr.results_finalized).to eq(PipelineRun::IN_PROGRESS)
    end

    it "creates a reduced set of output_states for nanopore" do
      pr = create(:pipeline_run, sample: sample, technology: PipelineRun::TECHNOLOGY_INPUT[:nanopore])
      expect(pr.output_states.pluck(:output)).to match_array(PipelineRun::TARGET_OUTPUTS[PipelineRun::TECHNOLOGY_INPUT[:nanopore]])
    end

    it "creates run stages only for illumina" do
      illumina = create(:pipeline_run, sample: sample, technology: PipelineRun::TECHNOLOGY_INPUT[:illumina])
      nanopore = create(:pipeline_run, sample: create(:sample, project: project, user: @joe), technology: PipelineRun::TECHNOLOGY_INPUT[:nanopore])
      expect(illumina.pipeline_run_stages.count).to eq(PipelineRunStage::STAGE_INFO.size)
      expect(nanopore.pipeline_run_stages.count).to eq(0)
    end
  end

  describe "#active_stage" do
    it "returns the first non-succeeded stage" do
      pr = create(:pipeline_run, sample: sample,
                                 pipeline_run_stages_data: [
                                   { step_number: 1, job_status: PipelineRunStage::STATUS_SUCCEEDED },
                                   { step_number: 2, job_status: PipelineRunStage::STATUS_STARTED },
                                 ])
      expect(pr.active_stage.step_number).to eq(2)
    end

    it "returns nil when all stages have succeeded" do
      pr = create(:pipeline_run, sample: sample,
                                 pipeline_run_stages_data: [
                                   { step_number: 1, job_status: PipelineRunStage::STATUS_SUCCEEDED },
                                   { step_number: 2, job_status: PipelineRunStage::STATUS_SUCCEEDED },
                                 ])
      expect(pr.active_stage).to be_nil
    end
  end

  describe "#host_filtering_stage" do
    it "returns the step_number 1 stage" do
      pr = create(:pipeline_run, sample: sample, technology: PipelineRun::TECHNOLOGY_INPUT[:illumina])
      expect(pr.host_filtering_stage.step_number).to eq(1)
    end
  end

  describe "#report_ready?" do
    it "is true when the report-ready output is loaded" do
      pr = create(:pipeline_run, sample: sample,
                                 output_states_data: [{ output: PipelineRun::REPORT_READY_OUTPUT, state: PipelineRun::STATUS_LOADED }])
      expect(pr.report_ready?).to be(true)
    end

    it "is false when the report-ready output is not loaded" do
      pr = create(:pipeline_run, sample: sample,
                                 output_states_data: [{ output: PipelineRun::REPORT_READY_OUTPUT, state: PipelineRun::STATUS_UNKNOWN }])
      expect(pr.report_ready?).to be(false)
    end
  end

  describe "#retry" do
    it "does nothing when the run has not failed" do
      pr = create(:pipeline_run, sample: sample, job_status: PipelineRun::STATUS_RUNNING, results_finalized: PipelineRun::IN_PROGRESS)
      expect(pr.retry).to be_nil
    end

    it "resets state on the active stage and the run when failed" do
      pr = create(:pipeline_run, sample: sample,
                                 job_status: PipelineRun::STATUS_FAILED,
                                 finalized: 1,
                                 results_finalized: PipelineRun::FINALIZED_FAIL,
                                 pipeline_run_stages_data: [
                                   { step_number: 1, job_status: PipelineRunStage::STATUS_FAILED, db_load_status: 1 },
                                 ],
                                 output_states_data: [
                                   { output: "taxon_counts", state: PipelineRun::STATUS_LOADED },
                                   { output: "ercc_counts", state: PipelineRun::STATUS_FAILED },
                                 ])
      pr.retry
      pr.reload
      expect(pr.finalized).to eq(0)
      expect(pr.results_finalized).to eq(PipelineRun::IN_PROGRESS)
      # LOADED outputs are preserved, others reset to UNKNOWN
      expect(pr.output_states.find_by(output: "taxon_counts").state).to eq(PipelineRun::STATUS_LOADED)
      expect(pr.output_states.find_by(output: "ercc_counts").state).to eq(PipelineRun::STATUS_UNKNOWN)
    end
  end

  describe "scopes and class queries" do
    it ".in_progress excludes failed and finalized runs" do
      running = create(:pipeline_run, sample: sample, job_status: PipelineRun::STATUS_RUNNING, finalized: 0)
      create(:pipeline_run, sample: sample, job_status: PipelineRun::STATUS_FAILED, finalized: 0)
      create(:pipeline_run, sample: sample, job_status: PipelineRun::STATUS_RUNNING, finalized: 1)
      expect(PipelineRun.in_progress).to include(running)
      expect(PipelineRun.in_progress.count).to eq(1)
    end

    it ".results_in_progress selects IN_PROGRESS runs" do
      in_progress = create(:pipeline_run, sample: sample, results_finalized: PipelineRun::IN_PROGRESS)
      create(:pipeline_run, sample: sample, results_finalized: PipelineRun::FINALIZED_SUCCESS)
      expect(PipelineRun.results_in_progress).to include(in_progress)
      expect(PipelineRun.results_in_progress).to all(have_attributes(results_finalized: PipelineRun::IN_PROGRESS))
    end

    it ".non_deprecated and .non_deleted filter appropriately" do
      kept = create(:pipeline_run, sample: sample, deprecated: false, deleted_at: nil)
      create(:pipeline_run, sample: sample, deprecated: true)
      deleted = create(:pipeline_run, sample: sample, deleted_at: Time.now.utc)
      expect(PipelineRun.non_deprecated).to include(kept)
      expect(PipelineRun.non_deprecated).not_to include(PipelineRun.find_by(deprecated: true))
      expect(PipelineRun.non_deleted).not_to include(deleted)
    end

    it ".top_completed_runs returns the max CHECKED run per sample" do
      create(:pipeline_run, sample: sample, job_status: PipelineRun::STATUS_RUNNING)
      checked = create(:pipeline_run, sample: sample, job_status: PipelineRun::STATUS_CHECKED)
      expect(PipelineRun.top_completed_runs).to include(checked)
    end

    it ".latest_by_sample returns the newest run per sample" do
      old = create(:pipeline_run, sample: sample, created_at: 2.days.ago)
      newest = create(:pipeline_run, sample: sample, created_at: 1.hour.ago)
      result = PipelineRun.latest_by_sample([sample])
      expect(result).to include(newest)
      expect(result).not_to include(old)
    end

    it ".viewable returns runs whose sample is viewable" do
      pr = create(:pipeline_run, sample: sample)
      expect(PipelineRun.viewable(@joe)).to include(pr)
    end

    it ".deletable returns finalized runs for the user" do
      pr = create(:pipeline_run, sample: sample, finalized: 1)
      expect(PipelineRun.deletable(@joe)).to include(pr)
    end
  end

  describe "version helpers" do
    it "#major_minor splits a version string" do
      pr = build(:pipeline_run, sample: sample)
      expect(pr.major_minor("1.5")).to eq([1, 5])
    end

    describe "#after" do
      let(:pr) { build(:pipeline_run, sample: sample) }

      it "returns true when v1 is nil" do
        expect(pr.after("1.0", nil)).to be(true)
      end

      it "returns false when v0 is nil" do
        expect(pr.after(nil, "1.0")).to be(false)
      end

      it "compares major then minor" do
        expect(pr.after("2.0", "1.9")).to be(true)
        expect(pr.after("1.4", "1.5")).to be(false)
        expect(pr.after("1.5", "1.5")).to be(true)
      end
    end

    describe "#multihit?" do
      it "is true for nanopore regardless of version" do
        pr = build(:pipeline_run, sample: sample, technology: PipelineRun::TECHNOLOGY_INPUT[:nanopore])
        expect(pr.multihit?).to be(true)
      end

      it "is true for illumina at pipeline version >= 1.5" do
        pr = build(:pipeline_run, sample: sample, technology: PipelineRun::TECHNOLOGY_INPUT[:illumina], pipeline_version: "3.7")
        expect(pr.multihit?).to be(true)
      end

      it "is false for old illumina versions" do
        pr = build(:pipeline_run, sample: sample, technology: PipelineRun::TECHNOLOGY_INPUT[:illumina], pipeline_version: "1.0")
        expect(pr.multihit?).to be(false)
      end
    end

    it "#assembly? is false for realistic versions" do
      pr = build(:pipeline_run, sample: sample, pipeline_version: "6.0.0")
      expect(pr.assembly?).to be(false)
    end
  end

  describe "workflow version / s3 subpath helpers" do
    let(:pr) do
      build(:pipeline_run, sample: sample, technology: PipelineRun::TECHNOLOGY_INPUT[:illumina], wdl_version: "6.10.0")
    end

    it "#workflow_version_tag combines workflow + wdl version" do
      expect(pr.workflow_version_tag).to eq("#{pr.workflow}-v6.10.0")
    end

    it "#version_key_subpath uses the wdl major version" do
      expect(pr.version_key_subpath).to eq("#{pr.workflow}-6")
    end

    it "#wdl_s3_folder uses the versioned workflow folder for recent versions" do
      pr.pipeline_version = "6.0.0"
      expect(pr.wdl_s3_folder).to eq("s3://#{S3_WORKFLOWS_BUCKET}/#{pr.workflow}-v6.10.0")
    end

    it "#wdl_s3_folder falls back to the legacy layout for old versions" do
      illumina = build(:pipeline_run, sample: sample, technology: PipelineRun::TECHNOLOGY_INPUT[:illumina], wdl_version: "4.0.0", pipeline_version: "4.0.0")
      expect(illumina.wdl_s3_folder).to eq("s3://#{S3_WORKFLOWS_BUCKET}/v4.0.0/#{WorkflowRun::WORKFLOW[:main]}")
    end
  end

  describe "sfn output/results paths" do
    it "#sfn_output_path is empty without an execution arn" do
      pr = build(:pipeline_run, sample: sample, sfn_execution_arn: nil)
      expect(pr.sfn_output_path).to eq("")
    end

    it "#sfn_output_path prefers s3_output_prefix" do
      pr = build(:pipeline_run, sample: sample, sfn_execution_arn: "fake-arn", s3_output_prefix: "s3://prefix")
      expect(pr.sfn_output_path).to eq("s3://prefix")
    end

    it "#sfn_results_path is empty when there is no output path" do
      pr = build(:pipeline_run, sample: sample, sfn_execution_arn: nil)
      expect(pr.sfn_results_path).to eq("")
    end

    it "#s3_file_for_sfn_result joins results path + filename" do
      pr = create(:pipeline_run, sample: sample, sfn_execution_arn: "fake-arn", s3_output_prefix: "s3://prefix", wdl_version: "6.0")
      expect(pr.s3_file_for_sfn_result("foo.json")).to eq("#{pr.sfn_results_path}/foo.json")
    end
  end

  describe "step-function path derivations" do
    let(:pr) do
      create(:pipeline_run, sample: sample,
                            sfn_execution_arn: "fake-arn",
                            s3_output_prefix: "s3://prefix",
                            wdl_version: "6.0",
                            pipeline_version: "6.0.0",
                            technology: PipelineRun::TECHNOLOGY_INPUT[:illumina])
    end

    it "routes host_filter/postprocess/assembly paths through sfn_results_path" do
      expect(pr.host_filter_output_s3_path).to eq(pr.sfn_results_path)
      expect(pr.postprocess_output_s3_path).to eq(pr.sfn_results_path)
      expect(pr.assembly_s3_path).to eq(pr.sfn_results_path)
      expect(pr.output_s3_path_with_version).to eq(pr.sfn_results_path)
      expect(pr.expt_output_s3_path).to eq(pr.sfn_results_path)
      expect(pr.coverage_viz_output_s3_path).to eq(pr.sfn_results_path)
      expect(pr.alignment_viz_output_s3_path).to eq(pr.sfn_results_path)
    end

    it "builds coverage viz + contig fasta + annotated fasta paths" do
      expect(pr.coverage_viz_summary_s3_path).to eq("#{pr.postprocess_output_s3_path}/#{PipelineRun::COVERAGE_VIZ_SUMMARY_JSON_NAME}")
      expect(pr.contigs_fasta_s3_path).to eq("#{pr.assembly_s3_path}/#{PipelineRun::ASSEMBLED_CONTIGS_NAME}")
      expect(pr.annotated_fasta_s3_path).to eq("#{pr.assembly_s3_path}/#{PipelineRun::ASSEMBLY_PREFIX}#{PipelineRun::DAG_ANNOTATED_FASTA_BASENAME}")
    end

    it "builds coverage viz data path for viz-enabled versions" do
      expect(pr.coverage_viz_data_s3_path("ACC1")).to eq("#{pr.coverage_viz_output_s3_path}/ACC1_coverage_viz.json")
    end

    it "builds alignment viz + longest reads paths" do
      expect(pr.alignment_viz_json_s3("nt.species.573")).to eq("#{pr.alignment_viz_output_s3_path}/nt.species.573.align_viz.json")
      expect(pr.five_longest_reads_fasta_s3("nt.species.573")).to eq("#{pr.alignment_viz_output_s3_path}/nt.species.573.longest_5_reads.fasta")
    end

    it "builds unidentified fasta path via the assembly branch" do
      # pipeline_version 6.0.0 supports assembly, so unidentified_fasta_s3_path
      # takes the first (assembly) branch: assembly_s3_path + ASSEMBLY_PREFIX + basename.
      expect(pr.unidentified_fasta_s3_path).to eq("#{pr.assembly_s3_path}/#{PipelineRun::ASSEMBLY_PREFIX}#{PipelineRun::DAG_UNIDENTIFIED_FASTA_BASENAME}")
    end

    it "provides tax-level/hit-type byterange paths" do
      paths = pr.s3_paths_for_taxon_byteranges
      expect(paths[TaxonCount::TAX_LEVEL_SPECIES]["NT"]).to include(PipelineRun::ASSEMBLY_PREFIX + PipelineRun::SORTED_TAXID_ANNOTATED_FASTA)
      expect(paths[TaxonCount::TAX_LEVEL_GENUS]["NR"]).to include(PipelineRun::SORTED_TAXID_ANNOTATED_FASTA_GENUS_NR)
    end

    describe "#ercc_output_path" do
      it "returns bowtie2 name for new-host-filtering bowtie2 versions" do
        pr.pipeline_version = "8.2"
        expect(pr.ercc_output_path).to eq(PipelineRun::BOWTIE2_ERCC_OUTPUT_NAME)
      end

      it "returns kallisto name for new-host-filtering non-bowtie2 versions" do
        pr.pipeline_version = "8.0"
        expect(pr.ercc_output_path).to eq(PipelineRun::KALLISTO_ERCC_OUTPUT_NAME)
      end

      it "returns the legacy star output name for old versions" do
        pr.pipeline_version = "6.0.0"
        expect(pr.ercc_output_path).to eq(PipelineRun::ERCC_OUTPUT_NAME)
      end
    end

    describe "#host_count_s3_path" do
      it "uses transcript reads for new host filtering versions" do
        pr.pipeline_version = "8.0"
        expect(pr.host_count_s3_path).to eq("#{pr.host_filter_output_s3_path}/#{PipelineRun::HOST_TRANSCRIPT_READS_OUTPUT_NAME}")
      end

      it "uses reads-per-gene for older versions" do
        pr.pipeline_version = "6.0.0"
        expect(pr.host_count_s3_path).to eq("#{pr.host_filter_output_s3_path}/#{PipelineRun::READS_PER_GENE_STAR_TAB_NAME}")
      end
    end
  end

  describe "#s3_file_for" do
    let(:pr) do
      create(:pipeline_run, sample: sample, sfn_execution_arn: "fake-arn", s3_output_prefix: "s3://prefix", wdl_version: "6.0", pipeline_version: "6.0.0")
    end

    it "maps outputs to their s3 paths" do
      expect(pr.s3_file_for("taxon_counts")).to eq("#{pr.assembly_s3_path}/#{PipelineRun::REFINED_TAXON_COUNTS_JSON_NAME}")
      expect(pr.s3_file_for("taxon_byteranges")).to eq("#{pr.assembly_s3_path}/#{PipelineRun::REFINED_TAXID_BYTERANGE_JSON_NAME}")
      expect(pr.s3_file_for("contigs")).to eq("#{pr.assembly_s3_path}/#{PipelineRun::ASSEMBLED_STATS_NAME}")
      expect(pr.s3_file_for("contig_counts")).to eq("#{pr.assembly_s3_path}/#{PipelineRun::CONTIG_SUMMARY_JSON_NAME}")
      expect(pr.s3_file_for("accession_coverage_stats")).to eq(pr.coverage_viz_summary_s3_path)
      expect(pr.s3_file_for("contig_bases")).to eq("#{pr.assembly_s3_path}/#{PipelineRun::CONTIG_BASE_COUNTS_NAME}")
    end

    it "returns nil when the resolved path is invalid (starts with /)" do
      allow(pr).to receive(:host_filter_output_s3_path).and_return("")
      allow(pr).to receive(:ercc_output_path).and_return("ercc.tsv")
      expect(pr.s3_file_for("ercc_counts")).to be_nil
    end
  end

  describe "output_ready? / file_generated" do
    let(:pr) { create(:pipeline_run, sample: sample, sfn_execution_arn: "fake-arn", s3_output_prefix: "s3://prefix", wdl_version: "6.0", pipeline_version: "6.0.0") }

    it "#file_generated returns false for blank or absolute-path inputs" do
      expect(pr.file_generated("")).to be(false)
      expect(pr.file_generated("/local/path")).to be(false)
      expect(pr.file_generated(nil)).to be(false)
    end

    it "#file_generated returns true when the aws s3 ls succeeds" do
      status = instance_double(Process::Status, exitstatus: 0)
      allow(Open3).to receive(:capture3).and_return(["", "", status])
      expect(pr.file_generated("s3://bucket/key")).to be(true)
    end

    it "#output_ready? delegates to file_generated with the output's s3 path" do
      allow(pr).to receive(:file_generated).and_return(true)
      expect(pr.output_ready?("taxon_counts")).to be(true)
    end
  end

  describe "output-state aggregation helpers" do
    # A pipeline_run auto-creates one OutputState per TARGET_OUTPUT (via the
    # after_create :create_output_states callback), all initially UNKNOWN. The
    # aggregation predicates inspect EVERY output_state, so rather than assume a
    # fixed set of target outputs (which can vary by technology / suite-order
    # factory state), drive each output_state directly off the persisted rows:
    # mark ercc_counts FAILED and everything else LOADED. This makes the
    # "all terminal" / "all loaded" / hash expectations robust to whatever the
    # full set of auto-created outputs happens to be.
    let(:pr) do
      run = create(:pipeline_run, sample: sample)
      run.output_states.each do |os|
        os.update!(state: os.output == "ercc_counts" ? PipelineRun::STATUS_FAILED : PipelineRun::STATUS_LOADED)
      end
      run
    end

    it "#all_output_states_terminal? is true when all are LOADED/FAILED" do
      expect(pr.all_output_states_terminal?).to be(true)
    end

    it "#all_output_states_loaded? is false when some outputs failed" do
      expect(pr.all_output_states_loaded?).to be(false)
    end

    it "#output_state_hash maps outputs to their states" do
      # Reload the association: the states were updated on fresh rows above, so
      # the pr's association cache (populated by create_output_states) may still
      # hold the pre-update rows.
      states_by_id = { pr.id => pr.output_states.reload.to_a }
      h = pr.output_state_hash(states_by_id)
      expect(h["taxon_counts"]).to eq(PipelineRun::STATUS_LOADED)
      expect(h["ercc_counts"]).to eq(PipelineRun::STATUS_FAILED)
    end

    describe "#status_display" do
      it "returns COMPLETE - ISSUE for known user errors" do
        pr.update(known_user_error: "FAULTY_INPUT")
        expect(pr.status_display({})).to eq("COMPLETE - ISSUE")
      end

      it "delegates to status_display_helper otherwise" do
        loaded = create(:pipeline_run, sample: sample,
                                       results_finalized: PipelineRun::FINALIZED_SUCCESS,
                                       output_states_data: [
                                         { output: "taxon_counts", state: PipelineRun::STATUS_LOADED },
                                         { output: "taxon_byteranges", state: PipelineRun::STATUS_LOADED },
                                       ])
        states_by_id = { loaded.id => loaded.output_states.to_a }
        expect(loaded.status_display(states_by_id)).to eq("COMPLETE")
      end
    end
  end

  describe "#job_status_display" do
    it "returns an initializing message when job_status is nil" do
      pr = build(:pipeline_run, sample: sample, job_status: nil)
      expect(pr.job_status_display).to eq("Pipeline Initializing")
    end

    it "extracts a running-stage message" do
      pr = build(:pipeline_run, sample: sample, job_status: "2.Minimap2/Diamond alignment-RUNNING")
      expect(pr.job_status_display).to eq("Running Minimap2/Diamond alignment")
    end

    it "returns the raw status when it does not match the stage pattern" do
      pr = build(:pipeline_run, sample: sample, job_status: "CHECKED")
      expect(pr.job_status_display).to eq("CHECKED")
    end
  end

  describe "timing helpers" do
    it "#run_time and #duration_hrs are derived from created_at" do
      pr = create(:pipeline_run, sample: sample, created_at: 2.hours.ago)
      expect(pr.run_time).to be > 0
      expect(pr.duration_hrs).to be_within(0.1).of(2.0)
    end

    it "#local_json_path uses the run id" do
      pr = create(:pipeline_run, sample: sample)
      expect(pr.local_json_path).to eq("#{PipelineRun::LOCAL_JSON_PATH}/#{pr.id}")
    end
  end

  describe "#check_and_log_long_run" do
    it "logs and sets alert_sent for runs over the threshold" do
      pr = create(:pipeline_run, sample: sample, created_at: 20.hours.ago, alert_sent: 0, job_status: "2.Minimap2/Diamond alignment-RUNNING")
      expect(Rails.logger).to receive(:error).with(match(/LongRunningSampleEvent/))
      pr.check_and_log_long_run
      expect(pr.reload.alert_sent).to eq(1)
    end

    it "does nothing when an alert was already sent" do
      pr = create(:pipeline_run, sample: sample, created_at: 20.hours.ago, alert_sent: 1)
      expect(Rails.logger).not_to receive(:error)
      pr.check_and_log_long_run
    end

    it "does nothing for short runs" do
      pr = create(:pipeline_run, sample: sample, created_at: 1.hour.ago, alert_sent: 0)
      expect(Rails.logger).not_to receive(:error)
      pr.check_and_log_long_run
    end
  end

  describe "subsampling + rpm/bpm helpers" do
    it "#subsampled_reads caps at the subsample max" do
      pr = build(:pipeline_run, sample: sample, subsample: 1000, fraction_subsampled: nil)
      allow(pr).to receive(:adjusted_remaining_reads).and_return(10_000_000)
      # subsample * number of fastq input files (2 in the sample factory)
      expect(pr.subsampled_reads).to eq(1000 * sample.input_files.fastq.count)
    end

    it "#subsampled_reads returns all remaining reads when under the cap" do
      pr = build(:pipeline_run, sample: sample, subsample: 10_000_000)
      allow(pr).to receive(:adjusted_remaining_reads).and_return(5)
      expect(pr.subsampled_reads).to eq(5)
    end

    it "#subsample_fraction prefers the stored fraction_subsampled" do
      pr = build(:pipeline_run, sample: sample, fraction_subsampled: 0.25)
      expect(pr.subsample_fraction).to eq(0.25)
    end

    it "#subsample_fraction computes the ratio when fraction_subsampled is nil" do
      pr = build(:pipeline_run, sample: sample, fraction_subsampled: nil, subsample: nil)
      allow(pr).to receive(:adjusted_remaining_reads).and_return(100)
      allow(pr).to receive(:subsampled_reads).and_return(50)
      expect(pr.subsample_fraction).to eq(0.5)
    end

    it "#rpm computes reads per million" do
      pr = build(:pipeline_run, sample: sample, total_reads: 2_000_000, total_ercc_reads: 0)
      allow(pr).to receive(:subsample_fraction).and_return(1.0)
      expect(pr.rpm(2)).to eq(1.0)
    end

    it "#bpm computes bases per million" do
      pr = build(:pipeline_run, sample: sample, total_bases: 2_000_000, fraction_subsampled_bases: 1.0)
      expect(pr.bpm(2)).to eq(1.0)
    end
  end

  describe "technology-specific count helpers" do
    it "#fetch_total_count_by_technology returns total_reads for illumina" do
      pr = build(:pipeline_run, sample: sample, technology: PipelineRun::TECHNOLOGY_INPUT[:illumina], total_reads: 42)
      expect(pr.fetch_total_count_by_technology).to eq(42)
    end

    it "#fetch_total_count_by_technology returns total_bases for nanopore" do
      pr = build(:pipeline_run, sample: sample, technology: PipelineRun::TECHNOLOGY_INPUT[:nanopore], total_bases: 99)
      expect(pr.fetch_total_count_by_technology).to eq(99)
    end

    it "#fetch_adjusted_total_count_by_technology adjusts for illumina" do
      pr = build(:pipeline_run, sample: sample, technology: PipelineRun::TECHNOLOGY_INPUT[:illumina], total_reads: 100, total_ercc_reads: 10)
      allow(pr).to receive(:subsample_fraction).and_return(0.5)
      expect(pr.fetch_adjusted_total_count_by_technology).to eq((100 - 10) * 0.5)
    end

    it "#fetch_adjusted_total_count_by_technology returns total_bases for nanopore" do
      pr = build(:pipeline_run, sample: sample, technology: PipelineRun::TECHNOLOGY_INPUT[:nanopore], total_bases: 77)
      expect(pr.fetch_adjusted_total_count_by_technology).to eq(77)
    end
  end

  describe "#compare_ercc_counts" do
    it "returns nil when there are no ercc counts" do
      pr = create(:pipeline_run, sample: sample)
      expect(pr.compare_ercc_counts).to be_nil
    end

    it "returns a baseline comparison with actual counts" do
      pr = create(:pipeline_run, sample: sample)
      baseline = ErccCount::BASELINE.first
      ErccCount.create!(pipeline_run: pr, name: baseline[:ercc_id], count: 5)
      result = pr.reload.compare_ercc_counts
      entry = result.find { |r| r[:name] == baseline[:ercc_id] }
      expect(entry[:actual]).to eq(5)
      expect(entry[:expected]).to eq(baseline[:concentration_in_mix_1_attomolesul])
    end
  end

  describe "#report_info_params and #max_updated_at" do
    it "returns default report info params" do
      pr = create(:pipeline_run, sample: sample, pipeline_version: "6.0.0")
      params = pr.report_info_params
      expect(params[:pipeline_version]).to eq("6.0.0")
      expect(params[:pipeline_run_id]).to eq(pr.id)
      expect(params[:format]).to eq("json")
    end

    it "falls back to PIPELINE_VERSION_WHEN_NULL when version is nil" do
      pr = create(:pipeline_run, sample: sample, pipeline_version: nil)
      expect(pr.report_info_params[:pipeline_version]).to eq(PipelineRun::PIPELINE_VERSION_WHEN_NULL)
    end

    it "#max_updated_at is at least the run's own updated_at" do
      pr = create(:pipeline_run, sample: sample)
      expect(pr.max_updated_at).to be >= pr.updated_at
    end
  end

  describe "#outputs_by_step dispatch" do
    it "returns an empty hash for an unrecognized execution strategy" do
      pr = create(:pipeline_run, sample: sample, pipeline_execution_strategy: PipelineRun.pipeline_execution_strategies[:step_function])
      allow(pr).to receive(:step_function?).and_return(false)
      allow(pr).to receive(:directed_acyclic_graph?).and_return(false)
      expect(pr.outputs_by_step).to eq({})
    end

    it "routes to sfn_outputs_by_step for step function runs" do
      pr = create(:pipeline_run, sample: sample)
      allow(pr).to receive(:sfn_outputs_by_step).and_return({ foo: "bar" })
      expect(pr.outputs_by_step).to eq({ foo: "bar" })
    end
  end

  describe "#sfn_error / #sfn_pipeline_error" do
    it "returns nil when there is no sfn output path" do
      pr = build(:pipeline_run, sample: sample, sfn_execution_arn: nil)
      expect(pr.sfn_error).to be_nil

      # With sfn_execution_arn nil, #sfn_output_path returns the empty string
      # "" (not nil). The `return unless sfn_output_path.present?` guard in
      # #sfn_pipeline_error correctly treats "" as absent and short-circuits to
      # a bare nil, consistent with #sfn_error. See app/models/pipeline_run.rb
      # #sfn_pipeline_error / #sfn_output_path.
      expect(pr.sfn_pipeline_error).to be_nil
    end

    it "delegates to SfnExecution#error when there is an output path" do
      pr = create(:pipeline_run, sample: sample, sfn_execution_arn: "fake-arn", s3_output_prefix: "s3://prefix", wdl_version: "6.0")
      fake_execution = instance_double(SfnExecution, error: "SOME_ERROR")
      allow(SfnExecution).to receive(:new).and_return(fake_execution)
      expect(pr.sfn_error).to eq("SOME_ERROR")
    end
  end

  describe "#cleanup_s3" do
    it "does nothing when there is no output path" do
      pr = build(:pipeline_run, sample: sample, sfn_execution_arn: nil)
      expect(S3Util).not_to receive(:delete_s3_prefix)
      pr.cleanup_s3
    end

    it "deletes the s3 prefix when present" do
      pr = create(:pipeline_run, sample: sample, sfn_execution_arn: "fake-arn", s3_output_prefix: "s3://prefix", wdl_version: "6.0")
      expect(S3Util).to receive(:delete_s3_prefix).with(pr.sfn_output_path)
      pr.cleanup_s3
    end
  end

  describe "#nonhost_fastq_s3_paths" do
    it "returns two files for paired-end illumina" do
      pr = create(:pipeline_run, sample: sample, sfn_execution_arn: "fake-arn", s3_output_prefix: "s3://prefix", wdl_version: "6.0",
                                 pipeline_version: "6.0.0", technology: PipelineRun::TECHNOLOGY_INPUT[:illumina])
      files = pr.nonhost_fastq_s3_paths
      expect(files.length).to eq(2)
      expect(files.first).to include("nonhost_R1.fastq")
    end

    it "returns the ONT nonhost reads file for nanopore" do
      ont_sample = create(:sample, project: project, user: @joe)
      pr = create(:pipeline_run, sample: ont_sample, sfn_execution_arn: "fake-arn", s3_output_prefix: "s3://prefix", wdl_version: "6.0",
                                 pipeline_version: "6.0.0", technology: PipelineRun::TECHNOLOGY_INPUT[:nanopore])
      expect(pr.nonhost_fastq_s3_paths).to include(PipelineRun::ONT_NONHOST_READS_NAME)
    end
  end

  describe "#previous_pipeline_runs_same_version" do
    it "returns other runs of the sample with the same version" do
      first = create(:pipeline_run, sample: sample, pipeline_version: "6.0.0")
      second = create(:pipeline_run, sample: sample, pipeline_version: "6.0.0")
      create(:pipeline_run, sample: sample, pipeline_version: "5.0.0")
      expect(second.previous_pipeline_runs_same_version).to include(first)
      expect(second.previous_pipeline_runs_same_version).not_to include(second)
      expect(second.previous_pipeline_runs_same_version.pluck(:pipeline_version).uniq).to eq(["6.0.0"])
    end
  end

  describe "#enqueue_new_pipeline_run" do
    it "enqueues a RestartPipelineForSample job" do
      pr = create(:pipeline_run, sample: sample)
      expect(Resque).to receive(:enqueue).with(RestartPipelineForSample, sample.id)
      pr.enqueue_new_pipeline_run
    end
  end
end
