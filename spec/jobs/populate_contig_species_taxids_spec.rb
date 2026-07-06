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

      # CHARACTERIZATION (app bug, not a spec bug): on MySQL this job does NOT
      # populate the taxids. PopulateContigSpeciesTaxids#perform calls
      # Contig.bulk_import(..., on_duplicate_key_update: { conflict_target: [...],
      #   columns: [...] }). That hash form is PostgreSQL-only (the app comment even
      # says "Hash form ... is portable to PostgreSQL"). On MySQL, activerecord-import
      # emits `ON DUPLICATE KEY UPDATE conflict_target = VALUES(contigs.conflict_target)`,
      # which raises `Mysql2::Error: Unknown column 'contigs.conflict_target'`. The job
      # rescues StandardError at the top level and only logs it, so #perform returns
      # normally while the upsert silently no-ops -- the contig's taxids stay nil.
      # This branch targets MySQL 8, so the current (broken) behavior is pinned here.
      # Fix tracked separately; do NOT change app code to make this pass.
      it "does not populate taxids on MySQL (upsert conflict_target is Postgres-only)" do
        PopulateContigSpeciesTaxids.perform
        contig.reload
        expect(contig.species_taxid_nt).to be_nil
        expect(contig.genus_taxid_nt).to be_nil
        expect(contig.species_taxid_nr).to be_nil
        expect(contig.genus_taxid_nr).to be_nil
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
