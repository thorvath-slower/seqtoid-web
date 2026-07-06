require 'rails_helper'

# Supplementary coverage for TaxonLineage (Coverage Wave 4b). Covers the
# instance level/name resolution and the small class helpers.
RSpec.describe TaxonLineage, type: :model do
  describe "#tax_level and #name" do
    it "resolves to the species level and species name when species_taxid > 0" do
      lineage = create(:taxon_lineage, species_taxid: 123, species_name: "Homo sapiens", genus_taxid: 0)
      expect(lineage.tax_level).to eq(TaxonCount::TAX_LEVEL_SPECIES)
      expect(lineage.name).to eq("Homo sapiens")
    end

    it "resolves to the genus level when only genus_taxid > 0" do
      lineage = create(:taxon_lineage, species_taxid: -100, genus_taxid: 456, genus_name: "Homo")
      expect(lineage.tax_level).to eq(TaxonCount::TAX_LEVEL_GENUS)
      expect(lineage.name).to eq("Homo")
    end
  end

  describe "#to_a and .names_a / .null_array" do
    it "#to_a returns the values for the ordered name columns" do
      lineage = create(:taxon_lineage, species_taxid: 1, genus_taxid: 2, superkingdom_name: "Eukaryota")
      row = lineage.to_a
      expect(row.length).to eq(TaxonLineage.names_a.length)
      expect(row.last).to eq("Eukaryota")
    end

    it ".null_array has one entry per name column" do
      expect(TaxonLineage.null_array.length).to eq(TaxonLineage.names_a.length)
    end
  end

  describe ".level_name" do
    it "maps species / genus / family levels to their names" do
      expect(TaxonLineage.level_name(TaxonCount::TAX_LEVEL_SPECIES)).to eq("species")
      expect(TaxonLineage.level_name(TaxonCount::TAX_LEVEL_GENUS)).to eq("genus")
      expect(TaxonLineage.level_name(TaxonCount::TAX_LEVEL_FAMILY)).to eq("family")
    end

    it "falls back to rank_<level> for other levels" do
      expect(TaxonLineage.level_name(7)).to eq("rank_7")
    end
  end

  describe "LineageNotFoundError" do
    it "includes the taxid in the message" do
      error = TaxonLineage::LineageNotFoundError.new(999)
      expect(error.message).to include("999")
    end
  end
end
