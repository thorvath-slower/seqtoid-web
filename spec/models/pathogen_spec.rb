require 'rails_helper'

RSpec.describe Pathogen, type: :model do
  context "persistence" do
    it "persists with a tax_id" do
      pathogen = Pathogen.create!(tax_id: 42)
      expect(pathogen).to be_persisted
      expect(pathogen.tax_id).to eq(42)
    end
  end

  context "ignored columns" do
    it "ignores the legacy citation_id column" do
      expect(Pathogen.ignored_columns).to include("citation_id")
    end
  end

  context "associations" do
    it "has and belongs to many pathogen_list_versions" do
      pathogen = Pathogen.create!(tax_id: 7)
      version = create(:pathogen_list_version, version: "0.1.0", pathogen_list_id: create(:pathogen_list).id)
      pathogen.pathogen_list_versions << version
      expect(pathogen.reload.pathogen_list_versions).to include(version)
    end
  end
end
