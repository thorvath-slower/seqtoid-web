require "rails_helper"

# Coverage Wave 5: ReportHelper is a mix of pure class methods (sort parsing,
# taxon-count reshaping/cleanup, negative-taxid name synthesis) plus a couple of
# instance methods for CSV generation. These are DB-light: we exercise the real
# branches with plain-hash fixtures shaped like the SQL rows the pipeline emits.
RSpec.describe ReportHelper do
  # A tiny host to reach the module's instance methods (generate_heatmap_csv, select_pipeline_run).
  let(:host) { Class.new { include ReportHelper }.new }
  let(:short_read) { WorkflowRun::WORKFLOW[:short_read_mngs] }
  let(:long_read) { WorkflowRun::WORKFLOW[:long_read_mngs] }

  describe ".decode_sort_by" do
    it "returns nil for a nil input" do
      expect(described_class.decode_sort_by(nil)).to be_nil
    end

    it "returns nil when the parts count is wrong" do
      expect(described_class.decode_sort_by("highest_NT")).to be_nil
    end

    it "returns nil for an invalid direction" do
      expect(described_class.decode_sort_by("sideways_nt_rpm")).to be_nil
    end

    it "returns nil for an invalid count type" do
      expect(described_class.decode_sort_by("highest_xx_rpm")).to be_nil
    end

    it "returns nil for an invalid metric" do
      expect(described_class.decode_sort_by("highest_nt_bogusmetric")).to be_nil
    end

    it "decodes a valid sort_by into its parts" do
      expect(described_class.decode_sort_by("highest_nt_rpm")).to eq(
        direction: "highest",
        count_type: "NT",
        metric: "rpm"
      )
    end
  end

  describe ".zero_metrics" do
    it "returns short-read-shaped zero metrics" do
      metrics = described_class.zero_metrics("NT", short_read)
      expect(metrics["count_type"]).to eq("NT")
      expect(metrics["r"]).to eq(0)
      expect(metrics).to have_key("zscore")
    end

    it "returns long-read-shaped zero metrics (bases based)" do
      metrics = described_class.zero_metrics("NR", long_read)
      expect(metrics["count_type"]).to eq("NR")
      expect(metrics).to have_key("b")
      expect(metrics).to have_key("bpm")
      expect(metrics).not_to have_key("zscore")
    end

    it "returns nil for an unknown workflow" do
      expect(described_class.zero_metrics("NT", "unknown-workflow")).to be_nil
    end
  end

  describe ".metric_props" do
    it "rounds present metric values and leaves zero-defaults otherwise" do
      taxon = { "count_type" => "NT", "r" => 5, "rpm" => 12.3456789012, "zscore" => 2.5 }
      props = described_class.metric_props(taxon, short_read)
      expect(props["r"]).to eq(5)
      expect(props["rpm"]).to eq(12.3456789) # rounded to DECIMALS (7)
      expect(props["zscore"]).to eq(2.5)
    end
  end

  describe ".convert_2d" do
    it "groups rows by tax_id and nests NT/NR metrics" do
      rows = [
        { "tax_id" => 100, "count_type" => "NT", "tax_level" => 1, "r" => 10 },
        { "tax_id" => 100, "count_type" => "NR", "tax_level" => 1, "r" => 20 },
      ]
      result = described_class.convert_2d(rows, short_read)
      expect(result.keys).to eq([100])
      expect(result[100]["NT"]["r"]).to eq(10)
      expect(result[100]["NR"]["r"]).to eq(20)
    end
  end

  describe ".cleanup_genus_ids!" do
    it "sets species_taxid to the tax_id for species level rows" do
      tax_2d = { 100 => { "tax_level" => TaxonCount::TAX_LEVEL_SPECIES } }
      described_class.cleanup_genus_ids!(tax_2d)
      expect(tax_2d[100]["species_taxid"]).to eq(100)
    end

    it "sets genus_taxid for genus level rows and the missing species sentinel" do
      tax_2d = { 200 => { "tax_level" => TaxonCount::TAX_LEVEL_GENUS } }
      described_class.cleanup_genus_ids!(tax_2d)
      expect(tax_2d[200]["genus_taxid"]).to eq(200)
      expect(tax_2d[200]["species_taxid"]).to eq(TaxonLineage::MISSING_SPECIES_ID)
    end

    it "sets family_taxid for family level rows" do
      tax_2d = { 300 => { "tax_level" => TaxonCount::TAX_LEVEL_FAMILY } }
      described_class.cleanup_genus_ids!(tax_2d)
      expect(tax_2d[300]["family_taxid"]).to eq(300)
    end
  end

  describe ".validate_names!" do
    it "assigns a synthesized name to unnamed positive taxa and maps category" do
      tax_2d = {
        100 => { "tax_level" => TaxonCount::TAX_LEVEL_SPECIES, "superkingdom_taxid" => 2 },
      }
      described_class.validate_names!(tax_2d)
      expect(tax_2d[100]["name"]).to match(/unnamed species taxon 100/)
      expect(tax_2d[100]["category_name"]).to eq("Bacteria")
      expect(tax_2d[100]).not_to have_key("superkingdom_taxid")
    end

    it "labels a generic negative tax_id and defaults category to Uncategorized" do
      tax_2d = {
        -1 => { "tax_level" => TaxonCount::TAX_LEVEL_SPECIES, "superkingdom_taxid" => nil },
      }
      described_class.validate_names!(tax_2d)
      expect(tax_2d[-1]["name"]).to eq("all taxa with neither family nor genus classification")
      expect(tax_2d[-1]["category_name"]).to eq("Uncategorized")
    end

    it "labels the blacklist genus id" do
      blacklist_id = TaxonLineage::BLACKLIST_GENUS_ID
      tax_2d = {
        blacklist_id => { "tax_level" => TaxonCount::TAX_LEVEL_GENUS, "superkingdom_taxid" => 2 },
      }
      described_class.validate_names!(tax_2d)
      expect(tax_2d[blacklist_id]["name"]).to eq("all artificial constructs")
    end
  end

  describe ".remove_homo_sapiens_counts!" do
    it "removes homo sapiens tax ids" do
      tax_2d = { 9606 => { "name" => "human" }, 100 => { "name" => "other" } }
      described_class.remove_homo_sapiens_counts!(tax_2d)
      expect(tax_2d.keys).to eq([100])
    end
  end

  describe ".remove_zscore" do
    it "nils out NT and NR zscores" do
      tax_2d = { 100 => { "NT" => { "zscore" => 5 }, "NR" => { "zscore" => 6 } } }
      described_class.remove_zscore(tax_2d)
      expect(tax_2d[100]["NT"]["zscore"]).to be_nil
      expect(tax_2d[100]["NR"]["zscore"]).to be_nil
    end
  end

  describe ".taxon_counts_cleanup" do
    let(:rows) do
      [
        { "tax_id" => 100, "count_type" => "NT", "tax_level" => TaxonCount::TAX_LEVEL_SPECIES, "superkingdom_taxid" => 2, "r" => 10 },
        { "tax_id" => 100, "count_type" => "NR", "tax_level" => TaxonCount::TAX_LEVEL_SPECIES, "superkingdom_taxid" => 2, "r" => 20 },
      ]
    end

    it "runs the full cleanup chain and returns cleaned 2d data" do
      result = described_class.taxon_counts_cleanup(rows, short_read)
      expect(result[100]["category_name"]).to eq("Bacteria")
      expect(result[100]["NT"]["r"]).to eq(10)
    end

    it "removes zscores when should_remove_zscore is true" do
      result = described_class.taxon_counts_cleanup(rows, short_read, true)
      expect(result[100]["NT"]["zscore"]).to be_nil
    end
  end

  describe ".convert_neg_taxid" do
    it "maps a very negative call id back to its parent id via modulo" do
      # Ruby's modulo takes the sign of the divisor (negative here), and the method
      # negates the result, so (BASE - 55) maps to +55.
      tax_id = TaxonLineage::INVALID_CALL_BASE_ID - 55
      expect(described_class.convert_neg_taxid(tax_id)).to eq(55)
    end

    it "returns the tax_id unchanged when above the threshold" do
      expect(described_class.convert_neg_taxid(-1)).to eq(-1)
    end
  end

  describe ".species_or_genus" do
    it "is true for species and genus levels" do
      expect(described_class.species_or_genus(TaxonCount::TAX_LEVEL_SPECIES)).to be(true)
      expect(described_class.species_or_genus(TaxonCount::TAX_LEVEL_GENUS)).to be(true)
    end

    it "is false for family level" do
      expect(described_class.species_or_genus(TaxonCount::TAX_LEVEL_FAMILY)).to be(false)
    end
  end

  describe "#generate_heatmap_csv" do
    let(:sample_taxa_hash) do
      [
        {
          name: "Sample A",
          sample_id: 1,
          taxons: [
            {
              "tax_id" => 100,
              "genus_name" => "Genus",
              "name" => "Taxon Name",
              "NT" => { "aggregatescore" => 9.0, "r" => 10, "rpm" => 5.5, "zscore" => 2.0 },
              "NR" => { "r" => 8, "rpm" => 4.4, "zscore" => 1.5 },
            },
          ],
        },
      ]
    end

    it "generates a CSV with headers and a background footer" do
      csv = host.generate_heatmap_csv(sample_taxa_hash, nil)
      expect(csv).to include("sample_name")
      expect(csv).to include("Taxon Name")
      expect(csv).to include("Background: None")
    end

    it "includes a known_pathogen column when pathogen flags are provided" do
      flags = { 1 => { 100 => [PipelineReportService::FLAG_KNOWN_PATHOGEN] } }
      csv = host.generate_heatmap_csv(sample_taxa_hash, nil, flags)
      expect(csv).to include("known_pathogen")
      rows = csv.lines
      # Header + one data row + footer; the data row should end with a 1 for the flagged taxon.
      expect(rows[1]).to match(/,1\s*$/)
    end

    it "handles a nil sample list gracefully" do
      csv = host.generate_heatmap_csv(nil, nil)
      expect(csv).to include("sample_name")
      expect(csv).to include("Background: None")
    end
  end

  describe "#select_pipeline_run" do
    let(:sample) { instance_double(Sample) }

    it "selects by version when a positive version is given" do
      expect(sample).to receive(:pipeline_run_by_version).with("2.0").and_return(:versioned)
      expect(host.select_pipeline_run(sample, "2.0")).to eq(:versioned)
    end

    it "falls back to the first pipeline run for a zero/blank version" do
      expect(sample).to receive(:first_pipeline_run).and_return(:first)
      expect(host.select_pipeline_run(sample, "0")).to eq(:first)
    end
  end
end
