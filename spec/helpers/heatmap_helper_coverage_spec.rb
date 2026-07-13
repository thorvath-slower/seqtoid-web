require "rails_helper"

# Coverage Wave 2: exercises the data-shaping paths of HeatmapHelper that the
# Wave 1 spec (heatmap_helper_spec.rb) did not reach — top_taxons_details,
# samples_taxons_details, taxa_details and fetch_samples_taxons_counts. The
# heavy SQL / ReportHelper seams are stubbed so the branching logic can be
# driven with small fixtures.
RSpec.describe HeatmapHelper, type: :helper do
  # A minimal taxon row as produced by ReportHelper.taxon_counts_cleanup, with
  # the NT/NR sub-hashes the helper indexes into.
  def taxon_row(tax_id:, nt_metric: 5.0, nr_metric: 1.0, nt_z: 2.0, nr_z: 3.0, tax_level: 1, genus_taxid: 100)
    {
      "tax_id" => tax_id,
      "genus_taxid" => genus_taxid,
      "tax_level" => tax_level,
      "NT" => { "rpm" => nt_metric, "zscore" => nt_z },
      "NR" => { "rpm" => nr_metric, "zscore" => nr_z },
    }
  end

  describe ".top_taxons_details" do
    it "aggregates candidate taxons across pipeline runs and sorts by max aggregate score" do
      pr = instance_double(PipelineRun, sample_id: 11)
      results_by_pr = {
        1 => { "pr" => pr, "taxon_counts" => [] },
      }

      rows = {
        1 => taxon_row(tax_id: 100, nt_metric: 9.0),
        2 => taxon_row(tax_id: 200, nt_metric: 3.0),
      }
      allow(ReportHelper).to receive(:taxon_counts_cleanup).and_return(rows)

      details = HeatmapHelper.top_taxons_details(results_by_pr, "highest_nt_rpm", WorkflowRun::WORKFLOW[:short_read_mngs])

      # Sorted by max_aggregate_score desc: tax 100 (9.0) before tax 200 (3.0).
      expect(details.map { |t| t["tax_id"] }).to eq([100, 200])
      expect(details.first["max_aggregate_score"]).to eq(9.0)
      # Each candidate records the sample's per-taxon tuple.
      expect(details.first["samples"]).to have_key(11)
    end

    it "returns an empty array when there are no results" do
      expect(HeatmapHelper.top_taxons_details({}, "highest_nt_rpm", WorkflowRun::WORKFLOW[:short_read_mngs])).to eq([])
    end
  end

  describe ".samples_taxons_details" do
    let(:sample) do
      instance_double(
        Sample,
        id: 11,
        name: "Sample A",
        metadata_with_base_type: { "foo" => "bar" },
        host_genome_name: "Human",
        initial_workflow: WorkflowRun::WORKFLOW[:short_read_mngs]
      )
    end

    it "returns only metadata for every sample when taxon_ids is empty" do
      results = HeatmapHelper.samples_taxons_details({}, [sample], [], [])
      expect(results.length).to eq(1)
      entry = results.first
      expect(entry[:sample_id]).to eq(11)
      expect(entry[:ercc_count]).to eq(0)
      expect(entry).not_to have_key(:taxons)
    end

    it "builds taxon detail rows for samples that have matching taxons" do
      pr = instance_double(
        PipelineRun,
        sample_id: 11,
        pipeline_version: "8.0",
        total_ercc_reads: 123
      )
      allow(pr).to receive(:alignment_config).and_return(instance_double("AlignmentConfig", name: "align-1"))

      rows = { 1 => taxon_row(tax_id: 100) }
      allow(ReportHelper).to receive(:taxon_counts_cleanup).and_return(rows)

      results_by_pr = { 1 => { "pr" => pr, "taxon_counts" => [] } }
      results = HeatmapHelper.samples_taxons_details(results_by_pr, [sample], [100], [])

      entry = results.find { |r| r[:sample_id] == 11 }
      expect(entry[:pipeline_version]).to eq("8.0")
      expect(entry[:alignment_config_name]).to eq("align-1")
      expect(entry[:ercc_count]).to eq(123)
      expect(entry[:taxons].map { |t| t["tax_id"] }).to eq([100])
      # apply_custom_filters with no filters marks the row not-filtered-out.
      expect(entry[:taxons].first[:filtered]).to be(true)
    end

    it "falls back to metadata-only for samples without a matching pipeline run result" do
      other_sample = instance_double(
        Sample,
        id: 22,
        name: "Sample B",
        metadata_with_base_type: {},
        host_genome_name: "Mosquito",
        initial_workflow: WorkflowRun::WORKFLOW[:short_read_mngs]
      )
      pr = instance_double(PipelineRun, sample_id: 11, pipeline_version: "8.0", total_ercc_reads: 0)
      allow(pr).to receive(:alignment_config).and_return(nil)
      allow(ReportHelper).to receive(:taxon_counts_cleanup).and_return({ 1 => taxon_row(tax_id: 100) })

      results_by_pr = { 1 => { "pr" => pr, "taxon_counts" => [] } }
      results = HeatmapHelper.samples_taxons_details(results_by_pr, [sample, other_sample], [100], [])

      fallback = results.find { |r| r[:sample_id] == 22 }
      expect(fallback[:ercc_count]).to eq(0)
      expect(fallback).not_to have_key(:taxons)
      # alignment_config nil -> alignment_config_name nil for the matched sample.
      matched = results.find { |r| r[:sample_id] == 11 }
      expect(matched[:alignment_config_name]).to be_nil
    end
  end

  describe ".taxa_details" do
    it "removes removedTaxonIds and delegates to fetch + samples_taxons_details" do
      sample = instance_double(Sample, id: 11)
      params = { taxonIds: [100, 200], removedTaxonIds: [200] }

      allow(HeatmapHelper).to receive(:fetch_samples_taxons_counts).and_return({})
      allow(HeatmapHelper).to receive(:samples_taxons_details).and_return([:done])

      result = HeatmapHelper.taxa_details(params, [sample], 3, false)

      expect(HeatmapHelper).to have_received(:fetch_samples_taxons_counts)
        .with([sample], [100], [], 3, update_background_only: false)
      expect(HeatmapHelper).to have_received(:samples_taxons_details)
        .with({}, [sample], [100], [])
      expect(result).to eq([:done])
    end

    it "defaults taxonIds/removedTaxonIds to empty arrays when absent" do
      allow(HeatmapHelper).to receive(:fetch_samples_taxons_counts).and_return({})
      allow(HeatmapHelper).to receive(:samples_taxons_details).and_return([])

      HeatmapHelper.taxa_details({}, [], 0, true)

      expect(HeatmapHelper).to have_received(:fetch_samples_taxons_counts)
        .with([], [], [], 0, update_background_only: true)
    end
  end

  describe ".fetch_samples_taxons_counts" do
    let(:sample) { instance_double(Sample) }

    before do
      allow(HeatmapHelper).to receive(:get_latest_pipeline_runs_for_samples).and_return({ 500 => 11 })
    end

    it "computes rpm and zscore and organizes rows by pipeline_run_id" do
      pr = instance_double(PipelineRun, total_reads: 1000, total_ercc_reads: 0)
      allow(pr).to receive(:rpm).with(50).and_return(12.5)
      allow(PipelineRun).to receive(:where).and_return(double(includes: [pr]))
      allow(pr).to receive(:id).and_return(500)

      sql_row = { "pipeline_run_id" => 500, "r" => 50, "mean" => 2.0, "stdev" => 3.0 }
      allow(HeatmapHelper).to receive(:samples_taxons_counts_query).and_return([sql_row])

      result = HeatmapHelper.fetch_samples_taxons_counts([sample], [100], [], 7)

      counts = result[500]["taxon_counts"]
      expect(counts.length).to eq(1)
      expect(counts.first["rpm"]).to eq(12.5)
      # zscore = (rpm - mean) / stdev = (12.5 - 2.0) / 3.0
      expect(counts.first["zscore"]).to be_within(1e-9).of((12.5 - 2.0) / 3.0)
    end

    it "uses the default zscore when stdev is nil (taxon absent from background)" do
      pr = instance_double(PipelineRun, total_reads: 1000, total_ercc_reads: 0, id: 500)
      allow(pr).to receive(:rpm).and_return(5.0)
      allow(PipelineRun).to receive(:where).and_return(double(includes: [pr]))

      sql_row = { "pipeline_run_id" => 500, "r" => 10, "mean" => nil, "stdev" => nil }
      allow(HeatmapHelper).to receive(:samples_taxons_counts_query).and_return([sql_row])

      result = HeatmapHelper.fetch_samples_taxons_counts([sample], [100], [], 7)
      expect(result[500]["taxon_counts"].first["zscore"]).to eq(ReportHelper::ZSCORE_WHEN_ABSENT_FROM_BACKGROUND)
    end

    it "clamps a very large zscore to ZSCORE_MAX" do
      pr = instance_double(PipelineRun, total_reads: 1000, total_ercc_reads: 0, id: 500)
      allow(pr).to receive(:rpm).and_return(1_000_000.0)
      allow(PipelineRun).to receive(:where).and_return(double(includes: [pr]))

      sql_row = { "pipeline_run_id" => 500, "r" => 10, "mean" => 0.0, "stdev" => 0.001 }
      allow(HeatmapHelper).to receive(:samples_taxons_counts_query).and_return([sql_row])

      result = HeatmapHelper.fetch_samples_taxons_counts([sample], [100], [], 7)
      expect(result[500]["taxon_counts"].first["zscore"]).to eq(ReportHelper::ZSCORE_MAX)
    end

    it "skips rows whose pipeline run has no total_reads" do
      pr = instance_double(PipelineRun, total_reads: nil, id: 500)
      allow(PipelineRun).to receive(:where).and_return(double(includes: [pr]))

      sql_row = { "pipeline_run_id" => 500, "r" => 10 }
      allow(HeatmapHelper).to receive(:samples_taxons_counts_query).and_return([sql_row])

      result = HeatmapHelper.fetch_samples_taxons_counts([sample], [100], [], 7)
      # The pr entry is created but no counts are appended.
      expect(result[500]["taxon_counts"]).to eq([])
    end

    it "routes to the background-only query when update_background_only is set" do
      pr = instance_double(PipelineRun, total_reads: nil, id: 500)
      allow(PipelineRun).to receive(:where).and_return(double(includes: [pr]))
      allow(HeatmapHelper).to receive(:background_metrics_query).and_return([])

      HeatmapHelper.fetch_samples_taxons_counts([sample], [100], nil, 7, update_background_only: true)
      expect(HeatmapHelper).to have_received(:background_metrics_query).with(7, { 500 => 11 }, [100])
    end

    it "builds a parent_ids clause when parent_ids are supplied" do
      pr = instance_double(PipelineRun, total_reads: nil, id: 500)
      allow(PipelineRun).to receive(:where).and_return(double(includes: [pr]))
      captured_clause = nil
      allow(HeatmapHelper).to receive(:samples_taxons_counts_query) do |_bg, _map, _taxa, clause|
        captured_clause = clause
        []
      end

      HeatmapHelper.fetch_samples_taxons_counts([sample], [100], [300, 400], 7)
      expect(captured_clause).to include("taxon_counts.tax_id in (300,400)")
    end
  end

  describe ".sample_taxons_dict" do
    it "parses array-style thresholdFilters without raising" do
      sample = instance_double(Sample, default_background_id: 9)
      params = {
        thresholdFilters: ['{"metric":"NT_rpm","value":"5","operator":">="}'],
      }
      allow(TopTaxonsSqlService).to receive(:call).and_return({})
      allow(HeatmapHelper).to receive(:top_taxons_details).and_return([])
      allow(HeatmapHelper).to receive(:samples_taxons_details).and_return([:ok])

      result = HeatmapHelper.sample_taxons_dict(params, [sample], 0)
      expect(result).to eq([:ok])
      # When background_id <= 0 the sample's default background is used.
      expect(TopTaxonsSqlService).to have_received(:call).with(
        [sample], 9, hash_including(min_reads: HeatmapHelper::MINIMUM_READ_THRESHOLD)
      )
    end

    it "applies preset filters (categories/subcategories/species/readSpecificity)" do
      sample = instance_double(Sample, default_background_id: 9)
      params = {
        presets: %w[categories subcategories species readSpecificity],
        categories: ["viruses"],
        subcategories: '{"Viruses":["Phage"]}',
        species: "1",
        readSpecificity: "1",
        thresholdFilters: "[]",
      }
      captured = nil
      allow(TopTaxonsSqlService).to receive(:call) do |_samples, _bg, kwargs|
        captured = kwargs
        {}
      end
      allow(HeatmapHelper).to receive(:top_taxons_details).and_return([])
      allow(HeatmapHelper).to receive(:samples_taxons_details).and_return([])

      HeatmapHelper.sample_taxons_dict(params, [sample], 4)

      expect(captured[:categories]).to eq(["viruses"])
      expect(captured[:include_phage]).to be(true)
      expect(captured[:read_specificity]).to eq("1")
      expect(captured[:taxon_level]).to eq(TaxonCount::TAX_LEVEL_SPECIES)
    end

    it "refetches at genus level and drops removedTaxonIds when taxons remain" do
      sample = instance_double(Sample, default_background_id: 9)
      params = { removedTaxonIds: ["200", "bad"], thresholdFilters: "[]" }

      allow(TopTaxonsSqlService).to receive(:call).and_return({})
      # top_taxons_details yields two taxa, one of which is removed.
      allow(HeatmapHelper).to receive(:top_taxons_details).and_return(
        [{ "tax_id" => 100, "genus_taxid" => 50 }, { "tax_id" => 200, "genus_taxid" => 60 }]
      )
      allow(HeatmapHelper).to receive(:fetch_samples_taxons_counts).and_return({})
      allow(HeatmapHelper).to receive(:samples_taxons_details).and_return([:ok])

      HeatmapHelper.sample_taxons_dict(params, [sample], 4)

      # genus (non-species) path -> parent_ids = unique genus_taxids; taxon 200 removed.
      expect(HeatmapHelper).to have_received(:fetch_samples_taxons_counts)
        .with([sample], [100], [50, 60], 4)
    end
  end
end
