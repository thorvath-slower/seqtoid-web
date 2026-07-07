# frozen_string_literal: true

require "rails_helper"

# Coverage Wave 3: branch sweep for TaxonCountsDataService. Targets the
# present? branches the main spec skips: background_id (adds the taxon_summaries
# join + z_score field) and include_lineage (adds the lineage join + fields).
RSpec.describe TaxonCountsDataService, type: :service do
  before do
    project = create(:project)
    @pipeline_run = create(:pipeline_run,
                           sample: create(:sample, project: project),
                           total_reads: 1000,
                           adjusted_remaining_reads: 1000,
                           subsample: 1_000_000,
                           fraction_subsampled: 1.0)

    @nt_species = create(:taxon_count, pipeline_run: @pipeline_run, tax_id: 573,
                                       tax_level: TaxonCount::TAX_LEVEL_SPECIES,
                                       count_type: TaxonCount::COUNT_TYPE_NT, count: 209)
  end

  describe "when a background_id is provided (the present? branch)" do
    it "joins taxon_summaries and returns a z_score field" do
      background = create(:background)
      create(:taxon_summary, background: background, tax_id: 573,
                             count_type: TaxonCount::COUNT_TYPE_NT,
                             tax_level: TaxonCount::TAX_LEVEL_SPECIES,
                             mean: 1.0, stdev: 1.0)

      result = TaxonCountsDataService.call(
        pipeline_run_ids: [@pipeline_run.id],
        background_id: background.id
      )
      nt_result = result.find { |r| r[:tax_id] == 573 }
      expect(nt_result).to have_key(:z_score)
    end
  end

  describe "when include_lineage is true (the present? branch)" do
    it "joins taxon_lineages and returns lineage fields" do
      # The pipeline_run's alignment_config lineage_version ("2022-01-01") must
      # fall within the lineage's version_start/version_end for the join to match.
      create(:taxon_lineage, taxid: 573,
                             version_start: "2022-01-01", version_end: "2022-01-01",
                             species_taxid: 573, species_name: "Klebsiella pneumoniae")

      result = TaxonCountsDataService.call(
        pipeline_run_ids: [@pipeline_run.id],
        include_lineage: true
      )
      expect(result).not_to be_empty
      expect(result.first).to have_key(:species_name)
    end
  end
end
