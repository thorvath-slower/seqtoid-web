require 'rails_helper'

# Supplementary coverage for HostGenome (Coverage Wave 4b). The stock
# host_genome_spec.rb only touches ERCC defaults and all_without_metadata_field.
RSpec.describe HostGenome, type: :model do
  describe ".s3_star_index_path_default / .s3_bowtie2_index_path_default" do
    it "point at the ERCC prefix" do
      expect(HostGenome.s3_star_index_path_default).to include(HostGenome::ERCC_DIRECTORY_PATH)
      expect(HostGenome.s3_star_index_path_default).to end_with(HostGenome::S3_STAR_INDEX_FILE)
      expect(HostGenome.s3_bowtie2_index_path_default).to end_with(HostGenome::S3_BOWTIE2_INDEX_FILE)
    end
  end

  describe "#ercc_only?" do
    it "is true for a host genome with ERCC index paths" do
      hg = create(:host_genome, name: "ErccOnly",
                                s3_star_index_path: HostGenome.s3_star_index_path_default,
                                s3_bowtie2_index_path: HostGenome.s3_bowtie2_index_path_default)
      expect(hg.ercc_only?).to eq(true)
    end

    it "is false for a host genome with real index paths" do
      hg = create(:host_genome, name: "RealHost",
                                s3_star_index_path: "s3://bucket/real/STAR_genome.tar",
                                s3_bowtie2_index_path: "s3://bucket/real/bowtie2_genome.tar")
      expect(hg.ercc_only?).to eq(false)
    end
  end

  describe "#show_as_option?" do
    it "is true when user is nil and deprecation_status is nil" do
      hg = create(:host_genome, name: "ShownHost", user: nil, deprecation_status: nil)
      expect(hg.show_as_option?).to eq(true)
    end

    it "is false when a deprecation status is set" do
      hg = create(:host_genome, name: "DeprecatedHost", user: nil, deprecation_status: 1)
      expect(hg.show_as_option?).to eq(false)
    end
  end

  describe "#as_json" do
    it "adds showAsOption and ercc_only by default" do
      hg = create(:host_genome, name: "JsonHost")
      json = hg.as_json
      expect(json).to have_key(:showAsOption)
      expect(json).to have_key(:ercc_only)
    end

    it "omits ercc_only when public option is set" do
      hg = create(:host_genome, name: "PublicJsonHost")
      json = hg.as_json(public: true)
      expect(json).to have_key(:showAsOption)
      expect(json).not_to have_key(:ercc_only)
    end
  end

  describe "validations" do
    it "rejects a name with invalid characters" do
      hg = build(:host_genome, name: "Bad@Name")
      expect(hg).not_to be_valid
      expect(hg.errors[:name]).to be_present
    end

    it "rejects a non-s3 star index path" do
      hg = build(:host_genome, name: "NonS3", s3_star_index_path: "/local/path")
      expect(hg).not_to be_valid
      expect(hg.errors[:s3_star_index_path]).to be_present
    end
  end
end
