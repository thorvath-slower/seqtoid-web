require "rails_helper"

RSpec.describe PopulateContigSpeciesTaxids, type: :job do
  create_users

  let(:project) { create(:project, users: [@joe]) }
  let(:sample) { create(:sample, project: project, user: @joe) }
  let(:pipeline_run) { create(:pipeline_run, sample: sample) }

  describe "#perform" do
    context "with contigs that have lineage data and null taxids" do
      let!(:contig) do
        create(:contig,
               pipeline_run: pipeline_run,
               name: "contig_1",
               lineage_json: { "NT" => [101, 201], "NR" => [102, 202] }.to_json,
               species_taxid_nt: nil,
               species_taxid_nr: nil)
      end

      it "populates the species and genus taxids from lineage_json" do
        PopulateContigSpeciesTaxids.perform
        contig.reload
        expect(contig.species_taxid_nt).to eq(101)
        expect(contig.genus_taxid_nt).to eq(201)
        expect(contig.species_taxid_nr).to eq(102)
        expect(contig.genus_taxid_nr).to eq(202)
      end
    end

    context "with a contig whose lineage_json is empty" do
      let!(:contig) do
        create(:contig,
               pipeline_run: pipeline_run,
               name: "empty_lineage",
               lineage_json: "{}",
               species_taxid_nt: nil,
               species_taxid_nr: nil)
      end

      it "leaves the taxids nil" do
        PopulateContigSpeciesTaxids.perform
        contig.reload
        expect(contig.species_taxid_nt).to be_nil
        expect(contig.species_taxid_nr).to be_nil
      end
    end

    context "when a contig already has populated taxids" do
      let!(:contig) do
        create(:contig,
               pipeline_run: pipeline_run,
               name: "already_done",
               lineage_json: { "NT" => [999], "NR" => [888] }.to_json,
               species_taxid_nt: 5,
               species_taxid_nr: 6)
      end

      it "does not overwrite it (excluded by the null filter)" do
        PopulateContigSpeciesTaxids.perform
        contig.reload
        expect(contig.species_taxid_nt).to eq(5)
        expect(contig.species_taxid_nr).to eq(6)
      end
    end

    it "does not raise when there are no contigs to update" do
      expect { PopulateContigSpeciesTaxids.perform }.not_to raise_error
    end
  end
end
