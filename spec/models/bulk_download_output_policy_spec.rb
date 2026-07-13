require "rails_helper"

# CZID-524 -- output allow-list enforcement on BulkDownload + classification helpers.
RSpec.describe BulkDownload, type: :model do
  create_users

  before do
    @project = create(:project, users: [@joe])
    @sample = create(:sample, project: @project, user: @joe)
  end

  context "download_type allow-list validation" do
    it "accepts a catalogued download type" do
      bd = build(:bulk_download, user: @joe, download_type: BulkDownloadTypesHelper::SAMPLE_OVERVIEW_BULK_DOWNLOAD_TYPE)
      expect(bd).to be_valid
    end

    it "rejects an uncatalogued download type" do
      bd = build(:bulk_download, user: @joe, download_type: "definitely_not_a_real_type")
      expect(bd).not_to be_valid
      expect(bd.errors[:download_type].join).to include("not an allowed download type")
    end
  end
end

RSpec.describe BulkDownloadTypesHelper do
  describe ".valid_bulk_download_type?" do
    it "is true for a catalogued type" do
      expect(described_class.valid_bulk_download_type?(BulkDownloadTypesHelper::SAMPLE_METADATA_BULK_DOWNLOAD_TYPE)).to be(true)
    end

    it "is false for an unknown type" do
      expect(described_class.valid_bulk_download_type?("bogus")).to be(false)
    end
  end

  describe ".release_restricted?" do
    it "flags the intermediate output type as restricted" do
      expect(described_class.release_restricted?(
               BulkDownloadTypesHelper::CONSENSUS_GENOME_INTERMEDIATE_OUTPUT_FILES_BULK_DOWNLOAD_TYPE
             )).to be(true)
    end

    it "does not flag a released report type" do
      expect(described_class.release_restricted?(BulkDownloadTypesHelper::SAMPLE_OVERVIEW_BULK_DOWNLOAD_TYPE)).to be(false)
    end
  end

  describe "VALID_BULK_DOWNLOAD_TYPES" do
    it "matches the catalogue keys" do
      # VALID_BULK_DOWNLOAD_TYPES derives from BULK_DOWNLOAD_TYPE_NAME_TO_DATA.keys, and that hash is
      # built via Hash[pluck(:type).zip(...)], which dedupes the couple of catalogue entries that share
      # a type (sample_taxon_report / combined_sample_taxon_results appear twice with different params).
      # Compare against the unique type set so the assertion reflects that dedup rather than failing on
      # the pre-existing duplicate rows.
      # BULK_DOWNLOAD_TYPES is a plain Array, so this is Enumerable#pluck + Array#uniq, not an AR query;
      # the Rails/UniqBeforePluck cop (which wants .distinct) does not apply here.
      catalogue_types = BulkDownloadTypesHelper::BULK_DOWNLOAD_TYPES.pluck(:type).uniq # rubocop:disable Rails/UniqBeforePluck
      expect(described_class::VALID_BULK_DOWNLOAD_TYPES).to match_array(catalogue_types)
    end
  end
end
