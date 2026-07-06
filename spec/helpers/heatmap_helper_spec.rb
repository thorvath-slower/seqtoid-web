require "rails_helper"

RSpec.describe HeatmapHelper, type: :helper do
  describe "#parse_custom_filters" do
    it "parses valid threshold filters" do
      parsed = HeatmapHelper.parse_custom_filters(
        [{ "metric" => "NT_rpm", "value" => "5", "operator" => ">=" }]
      )
      expect(parsed).to eq([{ count_type: "NT", metric: "rpm", value: 5.0, operator: ">=" }])
    end

    it "skips filters with non-numeric values" do
      allow(Rails.logger).to receive(:warn)
      parsed = HeatmapHelper.parse_custom_filters(
        [{ "metric" => "NR_zscore", "value" => "bad", "operator" => "<=" }]
      )
      expect(parsed).to be_empty
    end
  end

  describe "#apply_custom_filters" do
    let(:row) { { "NT" => { "rpm" => 10 }, "NR" => { "zscore" => 3 } } }

    it "returns true when no filters are provided" do
      expect(HeatmapHelper.apply_custom_filters(row, [])).to be true
    end

    it "returns true when the row satisfies a >= filter" do
      filters = [{ "metric" => "NT_rpm", "value" => "5", "operator" => ">=" }]
      expect(HeatmapHelper.apply_custom_filters(row, filters)).to be true
    end

    it "returns false when the row fails a >= filter" do
      filters = [{ "metric" => "NT_rpm", "value" => "50", "operator" => ">=" }]
      expect(HeatmapHelper.apply_custom_filters(row, filters)).to be false
    end

    it "returns false when the row exceeds a <= filter" do
      filters = [{ "metric" => "NR_zscore", "value" => "1", "operator" => "<=" }]
      expect(HeatmapHelper.apply_custom_filters(row, filters)).to be false
    end
  end

  describe "#compute_aggregate_scores_v2!" do
    it "sets NT/NR maxzscore to the max of the two zscores" do
      rows = [{ "NT" => { "zscore" => 2.0 }, "NR" => { "zscore" => 7.0 } }]
      HeatmapHelper.compute_aggregate_scores_v2!(rows)
      expect(rows[0]["NT"]["maxzscore"]).to eq 7.0
      expect(rows[0]["NR"]["maxzscore"]).to eq 7.0
    end
  end

  describe "#only_species_level_counts!" do
    it "keeps only species-level taxa" do
      taxon_counts_2d = {
        1 => { "tax_level" => TaxonCount::TAX_LEVEL_SPECIES },
        2 => { "tax_level" => TaxonCount::TAX_LEVEL_GENUS },
      }
      HeatmapHelper.only_species_level_counts!(taxon_counts_2d)
      expect(taxon_counts_2d.keys).to eq([1])
    end
  end

  describe "#sample_taxons_dict" do
    it "returns an empty hash when there are no samples" do
      expect(HeatmapHelper.sample_taxons_dict({}, [], 1)).to eq({})
    end
  end

  describe "#get_latest_pipeline_runs_for_samples" do
    it "maps the latest pipeline_run id to each sample id" do
      project = create(:project)
      sample = create(:sample, project: project)
      create(:pipeline_run, sample: sample)
      latest = create(:pipeline_run, sample: sample)

      result = HeatmapHelper.get_latest_pipeline_runs_for_samples(Sample.where(id: sample.id))
      expect(result).to eq({ latest.id => sample.id })
    end
  end

  describe "#samples_taxons_counts_query" do
    it "builds SQL scoped to the given pipeline runs and taxon ids" do
      captured = nil
      fake_relation = double("relation", to_a: [])
      allow(TaxonCount.connection).to receive(:select_all) do |sql|
        captured = sql
        fake_relation
      end

      HeatmapHelper.samples_taxons_counts_query(7, { 42 => 1 }, [100, 200], "")
      expect(captured).to include("pipeline_run_id IN (42)")
      expect(captured).to include("taxon_counts.tax_id IN (100,200)")
      expect(captured).to include("7   = taxon_summaries.background_id")
    end
  end

  describe "#background_metrics_query" do
    it "builds a background-only metrics query" do
      captured = nil
      allow(TaxonCount.connection).to receive(:select_all) do |sql|
        captured = sql
        double("relation", to_a: [])
      end

      HeatmapHelper.background_metrics_query(9, { 55 => 3 }, [300])
      expect(captured).to include("pipeline_run_id IN (55)")
      expect(captured).to include("taxon_counts.tax_id IN (300)")
      expect(captured).to include("9   = taxon_summaries.background_id")
    end
  end
end
