require "rails_helper"

RSpec.describe PipelineOutputsHelper, type: :helper do
  describe "#complement_seq" do
    it "complements ACGT bases and leaves other characters unchanged" do
      expect(helper.complement_seq("ACGT")).to eq("TGCA")
      expect(helper.complement_seq("ACGTN-")).to eq("TGCAN-")
      expect(helper.complement_seq("")).to eq("")
    end
  end

  describe "#generate_quality_string" do
    it "reports zero mismatches for identical strings" do
      quality_string, mismatches = helper.generate_quality_string("ACGT", "ACGT")
      expect(quality_string).to eq("    ")
      expect(mismatches).to eq(0)
    end

    it "marks mismatched positions with X and counts them" do
      quality_string, mismatches = helper.generate_quality_string("ACGT", "AGGT")
      expect(quality_string).to eq(" X  ")
      expect(mismatches).to eq(1)
    end

    it "treats N in either sequence as a match" do
      quality_string, mismatches = helper.generate_quality_string("ANGT", "ACGT")
      expect(quality_string).to eq("    ")
      expect(mismatches).to eq(0)
    end
  end

  describe "#parse_accession" do
    it "samples reads, records the count, and builds alignment strings" do
      # A single read: [read_id, read_seq, metrics(10), ref_seq(3-part)]
      accession_details = {
        "reads" => [
          [
            "read123/1",
            "ACGTACGT",
            # metrics: [0]=float, [1..7]=ints, [8..9]=floats. Indices 4/5 are the
            # aligned read start/end (1-based); 6/7 are ref start/end.
            ["1.5", "1", "2", "3", "2", "5", "10", "20", "0.1", "0.2"],
            ["AA", "ACGT", "TT"],
          ],
        ],
        "coverage_summary" => {},
      }

      result = helper.parse_accession(accession_details)

      expect(result["reads_count"]).to eq(1)
      expect(result["reads"].size).to eq(1)
      read = result["reads"].first
      expect(read["read_id"]).to eq("read123/1")
      expect(read["reversed"]).to eq(0)
      # metrics are coerced to numeric types
      expect(read["metrics"][0]).to be_a(Float)
      expect(read["metrics"][1]).to be_a(Integer)
      # alignment is [ref_seq_display, read_seq_display, quality_string_display]
      expect(read["alignment"].size).to eq(3)
      expect(read["alignment"][0]).to include("|")
    end

    it "reverses the read when ref start (metric 6) is greater than ref end (metric 7)" do
      accession_details = {
        "reads" => [
          [
            "read456/2",
            "ACGTACGT",
            ["1.5", "1", "2", "3", "2", "5", "20", "10", "0.1", "0.2"],
            ["AA", "ACGT", "TT"],
          ],
        ],
      }

      result = helper.parse_accession(accession_details)
      expect(result["reads"].first["reversed"]).to eq(1)
    end
  end

  describe "#parse_tree" do
    it "delegates a leaf dict (with reads) to parse_accession when not raw" do
      results = {}
      leaf = {
        "reads" => [
          [
            "r/1",
            "ACGTACGT",
            ["1.5", "1", "2", "3", "2", "5", "10", "20", "0.1", "0.2"],
            ["AA", "ACGT", "TT"],
          ],
        ],
      }
      helper.parse_tree(results, "taxid_1", leaf, false)
      expect(results["taxid_1"]["reads_count"]).to eq(1)
    end

    it "sorts coverage and reads in place when raw is true" do
      results = {}
      leaf = {
        "reads" => [
          ["r2", "seq", [nil, nil, nil, nil, nil, nil, "5"]],
          ["r1", "seq", [nil, nil, nil, nil, nil, nil, "2"]],
        ],
        "coverage_summary" => {
          "coverage" => { "10-20" => 1, "1-9" => 2 },
        },
      }
      helper.parse_tree(results, "taxid_1", leaf, true)
      sorted = results["taxid_1"]
      # reads sorted ascending by metrics[6]
      expect(sorted["reads"].first[0]).to eq("r1")
      # coverage sorted ascending by the low end of the range key
      expect(sorted["coverage_summary"]["coverage"].first[0]).to eq("1-9")
    end

    it "recurses into nested dicts until it finds leaves" do
      results = {}
      nested = {
        "genus_1" => {
          "species_1" => {
            "reads" => [
              [
                "r/1",
                "ACGTACGT",
                ["1.5", "1", "2", "3", "2", "5", "10", "20", "0.1", "0.2"],
                ["AA", "ACGT", "TT"],
              ],
            ],
          },
        },
      }
      helper.parse_tree(results, "root", nested, false)
      expect(results["species_1"]["reads_count"]).to eq(1)
    end
  end

  describe "#status_display_helper" do
    it "returns COMPLETE when both taxon outputs are loaded and results are finalized" do
      states = { "taxon_byteranges" => PipelineRun::STATUS_LOADED, "taxon_counts" => PipelineRun::STATUS_LOADED }
      status = helper.status_display_helper(states, PipelineRun::FINALIZED_SUCCESS, PipelineRun::TECHNOLOGY_INPUT[:illumina])
      expect(status).to eq("COMPLETE")
    end

    it "returns COMPLETE* when only taxon_counts loaded but finalized" do
      states = { "taxon_byteranges" => "PENDING", "taxon_counts" => PipelineRun::STATUS_LOADED }
      status = helper.status_display_helper(states, PipelineRun::FINALIZED_SUCCESS, PipelineRun::TECHNOLOGY_INPUT[:illumina])
      expect(status).to eq("COMPLETE*")
    end

    it "returns FAILED when finalized but nothing loaded" do
      states = { "taxon_byteranges" => "PENDING", "taxon_counts" => "PENDING" }
      status = helper.status_display_helper(states, PipelineRun::FINALIZED_FAIL, PipelineRun::TECHNOLOGY_INPUT[:illumina])
      expect(status).to eq("FAILED")
    end

    it "returns RUNNING for nanopore when not finalized" do
      status = helper.status_display_helper({}, 0, PipelineRun::TECHNOLOGY_INPUT[:nanopore])
      expect(status).to eq("RUNNING")
    end

    it "returns POST PROCESSING when taxon_counts loaded but not finalized (illumina)" do
      states = { "taxon_counts" => PipelineRun::STATUS_LOADED }
      status = helper.status_display_helper(states, 0, PipelineRun::TECHNOLOGY_INPUT[:illumina])
      expect(status).to eq("POST PROCESSING")
    end

    it "returns ALIGNMENT when ercc_counts loaded but not finalized" do
      states = { "ercc_counts" => PipelineRun::STATUS_LOADED }
      status = helper.status_display_helper(states, 0, PipelineRun::TECHNOLOGY_INPUT[:illumina])
      expect(status).to eq("ALIGNMENT")
    end

    it "returns HOST FILTERING as the fallback" do
      status = helper.status_display_helper({}, 0, PipelineRun::TECHNOLOGY_INPUT[:illumina])
      expect(status).to eq("HOST FILTERING")
    end
  end

  describe "#curate_pipeline_run_display" do
    it "returns nil for a nil pipeline_run" do
      expect(helper.curate_pipeline_run_display(nil)).to be_nil
    end

    it "reshapes version and titleizes host_subtracted" do
      pipeline_run = create(:pipeline_run, sample: create(:sample, project: create(:project)))
      allow(pipeline_run).to receive(:host_subtracted).and_return("human")

      display = helper.curate_pipeline_run_display(pipeline_run)
      expect(display["version"][:pipeline]).to eq(pipeline_run.pipeline_version)
      expect(display["version"][:alignment_db]).to eq(pipeline_run.alignment_config.name)
      expect(display["host_subtracted"]).to eq("Human")
    end

    it "labels ercc host_subtracted as 'ERCC only'" do
      pipeline_run = create(:pipeline_run, sample: create(:sample, project: create(:project)))
      allow(pipeline_run).to receive(:host_subtracted).and_return("ercc")

      display = helper.curate_pipeline_run_display(pipeline_run)
      expect(display["host_subtracted"]).to eq("ERCC only")
    end
  end

  describe "#get_presigned_s3_url" do
    it "returns nil when the bucket lookup raises" do
      allow(PipelineOutputsHelper::Client).to receive(:head_bucket).and_raise(StandardError)
      url = helper.get_presigned_s3_url(bucket_name: "b", key: "k", filename: "f", duration: 10)
      expect(url).to be_nil
    end
  end
end
