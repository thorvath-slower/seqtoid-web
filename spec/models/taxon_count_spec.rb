require 'rails_helper'

RSpec.describe TaxonCount, type: :model do
  let(:pipeline_run) { create(:pipeline_run, sample: create(:sample, project: create(:project))) }

  context "associations" do
    it "belongs to a pipeline_run" do
      tc = create(:taxon_count, pipeline_run: pipeline_run)
      expect(tc.pipeline_run).to eq(pipeline_run)
    end
  end

  context "validations" do
    it "is valid with factory defaults" do
      expect(build(:taxon_count, pipeline_run: pipeline_run)).to be_valid
    end

    it "requires a tax_level in the allowed set" do
      tc = build(:taxon_count, pipeline_run: pipeline_run, tax_level: 99)
      expect(tc).not_to be_valid
      expect(tc.errors[:tax_level]).to be_present
    end

    it "requires a count_type in the allowed set" do
      tc = build(:taxon_count, pipeline_run: pipeline_run, count_type: "XX")
      expect(tc).not_to be_valid
      expect(tc.errors[:count_type]).to be_present
    end

    it "accepts the merged count_type" do
      tc = build(:taxon_count, pipeline_run: pipeline_run, count_type: TaxonCount::COUNT_TYPE_MERGED)
      expect(tc).to be_valid
    end

    it "allows a nil source_count_type" do
      tc = build(:taxon_count, pipeline_run: pipeline_run, source_count_type: nil)
      expect(tc).to be_valid
    end

    it "rejects an invalid source_count_type" do
      tc = build(:taxon_count, pipeline_run: pipeline_run, source_count_type: "XX")
      expect(tc).not_to be_valid
      expect(tc.errors[:source_count_type]).to be_present
    end

    it "rejects a negative count" do
      tc = build(:taxon_count, pipeline_run: pipeline_run, count: -1)
      expect(tc).not_to be_valid
      expect(tc.errors[:count]).to be_present
    end

    it "rejects percent_identity outside 0..100" do
      tc = build(:taxon_count, pipeline_run: pipeline_run, percent_identity: 150)
      expect(tc).not_to be_valid
      expect(tc.errors[:percent_identity]).to be_present
    end

    it "rejects a negative alignment_length" do
      tc = build(:taxon_count, pipeline_run: pipeline_run, alignment_length: -1)
      expect(tc).not_to be_valid
      expect(tc.errors[:alignment_length]).to be_present
    end

    it "requires an e_value" do
      tc = build(:taxon_count, pipeline_run: pipeline_run, e_value: nil)
      expect(tc).not_to be_valid
      expect(tc.errors[:e_value]).to be_present
    end
  end

  context "level/name mappings" do
    it "maps names to levels" do
      expect(TaxonCount::NAME_2_LEVEL['species']).to eq(TaxonCount::TAX_LEVEL_SPECIES)
      expect(TaxonCount::NAME_2_LEVEL['superkingdom']).to eq(TaxonCount::TAX_LEVEL_SUPERKINGDOM)
    end

    it "inverts levels back to names" do
      expect(TaxonCount::LEVEL_2_NAME[TaxonCount::TAX_LEVEL_GENUS]).to eq('genus')
    end
  end

  context "scopes" do
    before do
      @nt_species = create(:taxon_count, pipeline_run: pipeline_run, count_type: "NT", tax_level: TaxonCount::TAX_LEVEL_SPECIES)
      @nr_genus = create(:taxon_count, pipeline_run: pipeline_run, count_type: "NR", tax_level: TaxonCount::TAX_LEVEL_GENUS)
    end

    it "#type filters by count_type" do
      expect(TaxonCount.type("NT")).to include(@nt_species)
      expect(TaxonCount.type("NT")).not_to include(@nr_genus)
    end

    it "#level filters by tax_level" do
      expect(TaxonCount.level(TaxonCount::TAX_LEVEL_GENUS)).to include(@nr_genus)
      expect(TaxonCount.level(TaxonCount::TAX_LEVEL_GENUS)).not_to include(@nt_species)
    end
  end
end
