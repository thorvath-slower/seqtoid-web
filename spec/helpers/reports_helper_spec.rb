require "rails_helper"

# Coverage for ReportsHelper (plural). Note this is distinct from ReportHelper
# (singular, app/lib/report_helper.rb). ReportsHelper builds made-up names for
# missing / blacklisted / negative taxon ids so they render + sort sensibly.
RSpec.describe ReportsHelper, type: :helper do
  before { allow(Rails.logger).to receive(:info); allow(Rails.logger).to receive(:warn) }

  describe ".convert_neg_taxid" do
    it "maps an id below the invalid-call base into the offset parent id" do
      # thres = -100_000_000. For -100_000_300, (tax_id % thres) == -300 (Ruby
      # modulo takes the divisor's sign), so -(that) == 300.
      expect(ReportsHelper.convert_neg_taxid(-100_000_300)).to eq(300)
    end

    it "leaves an id at or above the threshold unchanged" do
      expect(ReportsHelper.convert_neg_taxid(-50)).to eq(-50)
    end
  end

  describe ".validate_name" do
    let(:base_args) do
      {
        tax_id: 1,
        tax_level: TaxonCount::TAX_LEVEL_SPECIES,
        tax_name: "Escherichia coli",
        genus_tax_id: 561,
        parent_name: "Escherichia",
        pipeline_run_id: 42,
      }
    end

    it "returns nil name and empty missing for a well-formed positive taxon" do
      name, missing = ReportsHelper.validate_name(**base_args)
      expect(name).to be_nil
      expect(missing).to eq({})
    end

    it "names a positive taxon with no tax_name as unnamed" do
      name, missing = ReportsHelper.validate_name(**base_args.merge(tax_name: nil))
      expect(name).to eq("unnamed species taxon 1")
      expect(missing[:name]).to eq(1)
    end

    it "labels the blacklist genus id as artificial constructs" do
      name, missing = ReportsHelper.validate_name(
        **base_args.merge(tax_id: TaxonLineage::BLACKLIST_GENUS_ID, tax_level: TaxonCount::TAX_LEVEL_GENUS)
      )
      expect(name).to eq("all artificial constructs")
      expect(missing).to eq({})
    end

    it "appends the tax_id for an unmapped negative id above the invalid-call base" do
      # -999 is negative, not below INVALID_CALL_BASE_ID, not the blacklist genus,
      # not a MISSING_LINEAGE_ID value, and not MISSING_SPECIES_ID_ALT, so the id
      # is appended to the default 'neither family nor genus' name.
      name, = ReportsHelper.validate_name(**base_args.merge(tax_id: -999))
      expect(name).to eq("all taxa with neither family nor genus classification -999")
    end

    context "for species below the invalid-call base id" do
      let(:invalid_id) { TaxonLineage::INVALID_CALL_BASE_ID - 300 }

      it "uses the supplied genus parent name" do
        name, missing = ReportsHelper.validate_name(
          **base_args.merge(tax_id: invalid_id, parent_name: "Escherichia")
        )
        expect(name).to eq("non-species-specific reads in genus Escherichia")
        expect(missing).to eq({})
      end

      it "falls back to the genus tax id when no parent name is found" do
        name, missing = ReportsHelper.validate_name(
          **base_args.merge(tax_id: invalid_id, parent_name: nil, genus_tax_id: 561)
        )
        expect(name).to eq("non-species-specific reads in genus taxon 561")
        expect(missing[:parent]).to eq(561)
      end
    end

    context "for a family-level taxon below the invalid-call base id" do
      let(:invalid_id) { TaxonLineage::INVALID_CALL_BASE_ID - 400 }

      it "uses the converted negative tax id as the family parent when unnamed" do
        name, missing = ReportsHelper.validate_name(
          tax_id: invalid_id,
          tax_level: TaxonCount::TAX_LEVEL_FAMILY,
          tax_name: nil,
          genus_tax_id: nil,
          parent_name: nil,
          pipeline_run_id: 7
        )
        # parent_tax_id = convert_neg_taxid(invalid_id) = 400 (see convert_neg_taxid above)
        expect(name).to eq("non-family-specific reads in family taxon 400")
        expect(missing[:parent]).to eq(400)
      end
    end
  end

  describe ".fetch_parent_name" do
    it "returns the genus name for a species from the lineage lookup" do
      lineage = { 561 => { "genus_name" => "Escherichia" } }
      name = ReportsHelper.fetch_parent_name(
        TaxonCount::TAX_LEVEL_SPECIES, 1, { genus_tax_id: 561 }, lineage
      )
      expect(name).to eq("Escherichia")
    end

    it "returns nil for a species when the genus is absent from the lineage" do
      name = ReportsHelper.fetch_parent_name(
        TaxonCount::TAX_LEVEL_SPECIES, 1, { genus_tax_id: 999 }, {}
      )
      expect(name).to be_nil
    end

    it "returns the family name directly when the genus id is present in the lineage" do
      lineage = { 561 => { "family_name" => "Enterobacteriaceae" } }
      name = ReportsHelper.fetch_parent_name(
        TaxonCount::TAX_LEVEL_GENUS, 561, { species_tax_ids: [] }, lineage
      )
      expect(name).to eq("Enterobacteriaceae")
    end

    it "falls back to a species-derived family name when the genus id is undefined" do
      lineage = { 1234 => { "family_name" => "Fallbackaceae" } }
      name = ReportsHelper.fetch_parent_name(
        TaxonCount::TAX_LEVEL_GENUS, 999, { species_tax_ids: [1234] }, lineage
      )
      expect(name).to eq("Fallbackaceae")
    end

    it "returns nil for a genus when neither genus nor species lineage is present" do
      name = ReportsHelper.fetch_parent_name(
        TaxonCount::TAX_LEVEL_GENUS, 999, { species_tax_ids: [42] }, {}
      )
      expect(name).to be_nil
    end
  end

  describe ".fake_genus" do
    it "builds an ad hoc genus bucket named after the species and re-links the species" do
      tax_info = { name: "Escherichia coli", genus_tax_id: -200, tax_level: TaxonCount::TAX_LEVEL_SPECIES }
      fake = ReportsHelper.fake_genus(5, tax_info)

      expected_id = ReportsHelper::FAKE_GENUS_BASE - 5
      expect(fake[:name]).to eq("Ad hoc bucket for escherichia coli")
      expect(fake[:genus_tax_id]).to eq(expected_id)
      expect(fake[:tax_level]).to eq(TaxonCount::TAX_LEVEL_GENUS)
      # The original species is re-pointed at the fake genus.
      expect(tax_info[:genus_tax_id]).to eq(expected_id)
    end

    it "names the bucket after the tax_id when the species has no name" do
      fake = ReportsHelper.fake_genus(9, { name: nil, genus_tax_id: -200 })
      expect(fake[:name]).to eq("Ad hoc bucket for 9")
    end
  end

  describe ".cleanup_missing_genus_counts" do
    it "fabricates a genus for a species whose genus counts are missing" do
      species_counts = {
        5 => { name: "Escherichia coli", genus_tax_id: -200, tax_level: TaxonCount::TAX_LEVEL_SPECIES },
      }
      genus_counts = {}

      ReportsHelper.cleanup_missing_genus_counts(species_counts, genus_counts)

      fake_id = ReportsHelper::FAKE_GENUS_BASE - 5
      expect(genus_counts).to have_key(fake_id)
      expect(genus_counts[fake_id][:tax_level]).to eq(TaxonCount::TAX_LEVEL_GENUS)
    end

    it "leaves genus counts untouched when every species already has its genus" do
      species_counts = { 5 => { name: "E. coli", genus_tax_id: 561 } }
      genus_counts = { 561 => { name: "Escherichia" } }

      ReportsHelper.cleanup_missing_genus_counts(species_counts, genus_counts)
      expect(genus_counts.keys).to eq([561])
    end
  end

  describe ".validate_names" do
    it "renames a missing-name species in place and warns about missing names" do
      # counts is keyed by INTEGER tax level (TaxonCount::TAX_LEVEL_SPECIES), as
      # PipelineReportService passes it, so level_name resolves to "species".
      counts = {
        TaxonCount::TAX_LEVEL_SPECIES => {
          7 => { name: nil, genus_tax_id: 561 },
        },
      }
      lineage_by_tax_id = { 561 => { "genus_name" => "Escherichia" } }

      ReportsHelper.validate_names(counts, lineage_by_tax_id, 11)
      expect(counts[TaxonCount::TAX_LEVEL_SPECIES][7][:name]).to eq("unnamed species taxon 7")
      expect(Rails.logger).to have_received(:warn).with(/missing names/)
    end
  end
end
