require 'rails_helper'

RSpec.describe Contig, type: :model do
  let(:pipeline_run) { create(:pipeline_run, sample: create(:sample, project: create(:project))) }

  context "associations" do
    it "belongs to a pipeline_run" do
      contig = create(:contig, pipeline_run: pipeline_run)
      expect(contig.pipeline_run).to eq(pipeline_run)
    end

    it "is invalid without a pipeline_run" do
      contig = build(:contig, pipeline_run: nil)
      expect(contig).not_to be_valid
      expect(contig.errors[:pipeline_run]).to be_present
    end
  end

  context "validations" do
    it "is valid with all required attributes" do
      expect(build(:contig, pipeline_run: pipeline_run)).to be_valid
    end

    it "requires a sequence" do
      contig = build(:contig, pipeline_run: pipeline_run, sequence: nil)
      expect(contig).not_to be_valid
      expect(contig.errors[:sequence]).to be_present
    end

    it "requires lineage_json" do
      contig = build(:contig, pipeline_run: pipeline_run, lineage_json: nil)
      expect(contig).not_to be_valid
      expect(contig.errors[:lineage_json]).to be_present
    end

    it "rejects a negative read_count" do
      contig = build(:contig, pipeline_run: pipeline_run, read_count: -1)
      expect(contig).not_to be_valid
      expect(contig.errors[:read_count]).to be_present
    end

    it "allows a zero read_count" do
      contig = build(:contig, pipeline_run: pipeline_run, read_count: 0)
      expect(contig).to be_valid
    end
  end

  context "constants" do
    it "exposes the BLAST sequence character limit" do
      expect(Contig::BLAST_SEQUENCE_CHARACTER_LIMIT).to eq(7500)
    end

    it "exposes the contig filters" do
      expect(Contig::CONTIG_FILTERS).to eq(["contigs", "contig_r"])
    end
  end

  context "#fa_header" do
    it "builds a FASTA header from name, read_count, and lineage_json" do
      contig = build(:contig, pipeline_run: pipeline_run, name: "contig_1",
                              read_count: 5, lineage_json: "{}")
      expect(contig.fa_header).to eq(">contig_1:5:{}\n")
    end
  end

  context "#to_fa" do
    it "concatenates the FASTA header and sequence" do
      contig = build(:contig, pipeline_run: pipeline_run, name: "contig_1",
                              read_count: 5, lineage_json: "{}", sequence: "GATTACA")
      expect(contig.to_fa).to eq(">contig_1:5:{}\nGATTACA")
    end
  end

  context "#middle_n_base_pairs" do
    # NOTE (reported to #294): the model comment says "If n > sequence.length, the
    # sequence is returned", but the slice arithmetic produces a negative start
    # offset for large n, so String#slice actually returns nil. This test pins the
    # ACTUAL current behavior; it documents the mismatch rather than the intent.
    it "returns nil when n greatly exceeds the sequence length (documents current behavior)" do
      contig = build(:contig, pipeline_run: pipeline_run, sequence: "GATTACA")
      expect(contig.middle_n_base_pairs(100)).to be_nil
    end

    it "returns a substring of the sequence for n smaller than the sequence length" do
      contig = build(:contig, pipeline_run: pipeline_run, sequence: "GATTACA")
      # Derived from the model's slice arithmetic, not hardcoded intent.
      result = contig.middle_n_base_pairs(3)
      expect(result).to be_a(String)
      expect("GATTACA").to include(result)
      expect(result.length).to be <= "GATTACA".length
    end
  end
end
