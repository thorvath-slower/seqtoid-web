require 'rails_helper'

RSpec.describe Citation, type: :model do
  def build_citation(**attrs)
    Citation.new({ key: "niaid_2020", footnote: "Some MLA footnote." }.merge(attrs))
  end

  context "validations" do
    it "is valid with a key and footnote" do
      expect(build_citation).to be_valid
    end

    it "requires a key" do
      citation = build_citation(key: nil)
      expect(citation).not_to be_valid
      expect(citation.errors[:key]).to include("can't be blank")
    end

    it "enforces case-insensitive uniqueness of key" do
      build_citation(key: "niaid_2020").save!
      dup = build_citation(key: "NIAID_2020")
      expect(dup).not_to be_valid
      expect(dup.errors[:key]).to be_present
    end
  end

  context "associations" do
    it "has and belongs to many pathogen_list_versions" do
      citation = build_citation
      citation.save!
      version = create(:pathogen_list_version, version: "0.1.0", pathogen_list_id: create(:pathogen_list).id)
      citation.pathogen_list_versions << version
      expect(citation.reload.pathogen_list_versions).to include(version)
    end
  end
end
