require "rails_helper"

RSpec.describe TaxonCountsDataService, type: :service do
  before do
    project = create(:project)
    @pipeline_run = create(:pipeline_run,
                           sample: create(:sample, project: project),
                           total_reads: 1000,
                           adjusted_remaining_reads: 1000,
                           subsample: 1_000_000,
                           fraction_subsampled: 1.0)

    # Species-level NT + NR count for tax 573
    @nt_species = create(:taxon_count, pipeline_run: @pipeline_run, tax_id: 573, tax_level: TaxonCount::TAX_LEVEL_SPECIES, count_type: TaxonCount::COUNT_TYPE_NT, count: 209)
    @nr_species = create(:taxon_count, pipeline_run: @pipeline_run, tax_id: 573, tax_level: TaxonCount::TAX_LEVEL_SPECIES, count_type: TaxonCount::COUNT_TYPE_NR, count: 69)
    # Genus-level NT count for tax 570
    @nt_genus = create(:taxon_count, pipeline_run: @pipeline_run, tax_id: 570, tax_level: TaxonCount::TAX_LEVEL_GENUS, count_type: TaxonCount::COUNT_TYPE_NT, count: 217)
    # A family-level count (tax_level 3) that should be filtered out
    create(:taxon_count, pipeline_run: @pipeline_run, tax_id: 91_347, tax_level: 3, count_type: TaxonCount::COUNT_TYPE_NT, count: 300)
    # A blacklisted-genus count that should be filtered out
    create(:taxon_count, pipeline_run: @pipeline_run, tax_id: TaxonLineage::BLACKLIST_GENUS_ID, tax_level: TaxonCount::TAX_LEVEL_GENUS, count_type: TaxonCount::COUNT_TYPE_NT, count: 5)
  end

  describe "#call" do
    it "returns species- and genus-level NT/NR counts for the pipeline run" do
      result = TaxonCountsDataService.call(pipeline_run_ids: [@pipeline_run.id])

      returned_tax_ids = result.map { |r| r[:tax_id] }.uniq
      expect(returned_tax_ids).to contain_exactly(573, 570)
      # Two entries for 573 (NT + NR) and one for 570 (NT)
      expect(result.length).to eq(3)
    end

    it "filters out tax_levels other than species and genus" do
      result = TaxonCountsDataService.call(pipeline_run_ids: [@pipeline_run.id])
      expect(result.map { |r| r[:tax_id] }).not_to include(91_347)
    end

    it "filters out blacklisted genus ids" do
      result = TaxonCountsDataService.call(pipeline_run_ids: [@pipeline_run.id])
      expect(result.map { |r| r[:tax_id] }).not_to include(TaxonLineage::BLACKLIST_GENUS_ID)
    end

    it "includes an rpm value derived from the count" do
      result = TaxonCountsDataService.call(pipeline_run_ids: [@pipeline_run.id])
      nt_573 = result.find { |r| r[:tax_id] == 573 && r[:count_type] == "NT" }

      # rpm = count / ((total_reads - total_ercc_reads) * fraction_subsampled) * 1e6
      # = 209 / ((1000 - 0) * 1.0) * 1_000_000 = 209_000
      expect(nt_573[:rpm]).to be_within(0.1).of(209_000.0)
    end

    context "when count_types filter is provided" do
      it "only returns the requested count type" do
        result = TaxonCountsDataService.call(
          pipeline_run_ids: [@pipeline_run.id],
          count_types: [TaxonCount::COUNT_TYPE_NR]
        )
        expect(result.map { |r| r[:count_type] }.uniq).to eq(["NR"])
        expect(result.map { |r| r[:tax_id] }).to contain_exactly(573)
      end
    end

    context "when taxon_ids filter is provided" do
      it "restricts results to those taxa" do
        result = TaxonCountsDataService.call(
          pipeline_run_ids: [@pipeline_run.id],
          taxon_ids: [570]
        )
        expect(result.map { |r| r[:tax_id] }.uniq).to eq([570])
      end
    end

    context "when lazy is true" do
      it "returns the relation and fields instead of executing the pluck" do
        relation, fields = TaxonCountsDataService.call(pipeline_run_ids: [@pipeline_run.id], lazy: true)

        expect(relation).to be_a(ActiveRecord::Relation)
        expect(fields).to include(:tax_id, :count, :count_type)
      end
    end

    context "when there are no matching taxon counts" do
      it "returns an empty array" do
        empty_run = create(:pipeline_run, sample: create(:sample, project: create(:project)))
        result = TaxonCountsDataService.call(pipeline_run_ids: [empty_run.id])
        expect(result).to eq([])
      end
    end
  end
end
