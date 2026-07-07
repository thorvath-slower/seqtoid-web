require "rails_helper"

# Coverage Wave 2: exercises the metadata CSV validation pipeline in
# MetadataHelper (validate_metadata_csv_for_* wrappers, the private
# validate_metadata_csv_for_samples, and find_or_create_host_genomes) plus
# official_metadata_fields_helper — paths the Wave 1 spec did not reach.
RSpec.describe MetadataHelper, type: :helper do
  before { allow(Rails.logger).to receive(:warn) }

  describe "#official_metadata_fields_helper" do
    it "returns the field_info for the union of required/default/core fields" do
      # A required field must also be default/core/default_for_new_host_genome
      # (see MetadataField#metadata_field_validations); a default field must be core.
      create(:metadata_field, name: "req_field", is_required: 1, is_default: 1, is_core: 1, default_for_new_host_genome: 1)
      create(:metadata_field, name: "def_field", is_default: 1, is_core: 1)
      create(:metadata_field, name: "core_only_field", is_core: 1)

      infos = helper.official_metadata_fields_helper
      names = infos.map { |i| i[:key] }
      expect(names).to include("req_field", "def_field", "core_only_field")
    end
  end

  describe "#validate_metadata_csv_for_project_samples" do
    let(:project) { create(:project) }
    let!(:host_genome) { create(:host_genome, name: "Human") }

    it "returns a missing-column-header error when a header is blank" do
      sample = create(:sample, project: project, name: "sample_1")
      metadata = { "headers" => ["sample_name", ""], "rows" => [] }

      result = helper.validate_metadata_csv_for_project_samples([sample], metadata)
      expect(result["errors"]).to include(ErrorHelper::MetadataValidationErrors::MISSING_COLUMN_HEADER)
    end

    it "returns a missing-sample-name-column error when no sample name column exists" do
      sample = create(:sample, project: project, name: "sample_1")
      metadata = { "headers" => %w[collection_date], "rows" => [] }

      result = helper.validate_metadata_csv_for_project_samples([sample], metadata)
      expect(result["errors"]).to include(ErrorHelper::MetadataValidationErrors::MISSING_SAMPLE_NAME_COLUMN)
    end

    it "validates a well-formed row against an existing sample with no errors" do
      field = create(:metadata_field, name: "sample_type", display_name: "Sample Type", base_type: MetadataField::STRING_TYPE)
      project.metadata_fields << field
      sample = create(:sample, project: project, name: "sample_1")
      sample.host_genome.metadata_fields << field unless sample.host_genome.metadata_fields.include?(field)

      metadata = {
        "headers" => %w[sample_name sample_type],
        "rows" => [%w[sample_1 Serum]],
      }

      result = helper.validate_metadata_csv_for_project_samples([sample], metadata)
      expect(result[:errors]).to be_empty
    end

    it "reports a row that references a sample name not present in the project" do
      sample = create(:sample, project: project, name: "sample_1")
      metadata = {
        "headers" => %w[sample_name],
        "rows" => [%w[nonexistent_sample]],
      }

      result = helper.validate_metadata_csv_for_project_samples([sample], metadata)
      captions = result[:errors].map { |g| g[:caption] }.join(" ")
      expect(captions).to match(/do not match any samples|does not match/i)
    end

    it "reports a duplicated sample row" do
      sample = create(:sample, project: project, name: "sample_1")
      metadata = {
        "headers" => %w[sample_name],
        "rows" => [%w[sample_1], %w[sample_1]],
      }

      result = helper.validate_metadata_csv_for_project_samples([sample], metadata)
      expect(result[:errors]).not_to be_empty
    end

    it "skips fully-empty rows without error" do
      sample = create(:sample, project: project, name: "sample_1")
      metadata = {
        "headers" => %w[sample_name],
        "rows" => [["", ""], %w[sample_1]],
      }

      result = helper.validate_metadata_csv_for_project_samples([sample], metadata)
      expect(result[:errors]).to be_empty
    end
  end

  describe "#validate_metadata_csv_for_new_samples" do
    let(:project) { create(:project) }
    let!(:human) { create(:host_genome, name: "Human") }

    it "returns a missing-host-genome-column error when host organism column is absent" do
      sample = create(:sample, project: project, name: "sample_1", host_genome: human)
      metadata = { "headers" => %w[sample_name], "rows" => [] }

      issues, new_host_genomes = helper.validate_metadata_csv_for_new_samples([sample], metadata)
      # The early-return path uses STRING keys ({ "errors" => ... }); the normal
      # completion path uses symbol keys ({ errors: ... }). This missing-column
      # bail-out hits the string-keyed variant.
      expect(issues["errors"]).to include(ErrorHelper::MetadataValidationErrors::MISSING_HOST_GENOME_COLUMN)
      expect(new_host_genomes).to eq([])
    end

    it "creates and returns a new host genome for an unknown host organism (new samples allow new host genomes)" do
      allow(helper).to receive(:current_user).and_return(create(:user))
      sample = create(:sample, project: project, name: "sample_1", host_genome: human)
      metadata = {
        "headers" => ["sample_name", "Host Organism"],
        "rows" => [["sample_1", "NoSuchOrganism"]],
      }

      issues, new_host_genomes = helper.validate_metadata_csv_for_new_samples([sample], metadata)
      # The new-samples wrapper passes allow_new_host_genomes=true, so an unknown
      # organism is initialized (not errored) and surfaced for the caller to save.
      expect(new_host_genomes.map(&:name)).to include("NoSuchOrganism")
      expect(issues).to have_key(:errors)
    end

    it "resolves a known host organism and returns it among the new_host_genomes candidates" do
      allow(helper).to receive(:current_user).and_return(create(:user))
      sample = create(:sample, project: project, name: "sample_1", host_genome: human)
      metadata = {
        "headers" => ["sample_name", "Host Organism"],
        "rows" => [["sample_1", "Human"]],
      }

      issues, new_host_genomes = helper.validate_metadata_csv_for_new_samples([sample], metadata)
      # find_or_create_host_genomes returns all found-or-created genomes, so the
      # existing Human is included as a candidate.
      expect(new_host_genomes.map(&:name)).to include("Human")
      expect(issues).to have_key(:errors)
    end
  end

  describe "#find_or_create_host_genomes" do
    let!(:human) { create(:host_genome, name: "Human") }

    it "looks up existing host genomes by name when new host genomes are disallowed" do
      metadata = {
        "headers" => ["sample_name", "Host Organism"],
        "rows" => [["s1", "Human"]],
      }

      host_genomes, hg_index, new_host_genomes = helper.send(:find_or_create_host_genomes, metadata, false)
      expect(hg_index).to eq(1)
      expect(host_genomes.map(&:name)).to include("Human")
      expect(new_host_genomes).to eq([])
    end

    it "builds new (unsaved) host genomes when allowed" do
      allow(helper).to receive(:current_user).and_return(create(:user))
      metadata = {
        "headers" => ["sample_name", "Host Organism"],
        "rows" => [["s1", "BrandNewOrganism"]],
      }

      host_genomes, _hg_index, new_host_genomes = helper.send(:find_or_create_host_genomes, metadata, true)
      expect(new_host_genomes.map(&:name)).to include("BrandNewOrganism")
      # find_or_create returns the found/created hg (or false if invalid) per row.
      expect(host_genomes).not_to be_empty
    end

    it "raises when a proposed host genome name exceeds 256 characters" do
      allow(helper).to receive(:current_user).and_return(create(:user))
      long_name = "x" * 257
      metadata = {
        "headers" => ["sample_name", "Host Organism"],
        "rows" => [["s1", long_name]],
      }

      expect { helper.send(:find_or_create_host_genomes, metadata, true) }
        .to raise_error(StandardError, /exceeds 256 characters/)
    end
  end
end
