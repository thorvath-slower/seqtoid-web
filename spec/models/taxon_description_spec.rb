require 'rails_helper'

RSpec.describe TaxonDescription, type: :model do
  def build_description(**attrs)
    TaxonDescription.new({ taxid: 562, wikipedia_id: 24_390 }.merge(attrs))
  end

  context "validations" do
    it "is valid with a wikipedia_id" do
      expect(build_description).to be_valid
    end

    it "requires a wikipedia_id" do
      description = build_description(wikipedia_id: nil)
      expect(description).not_to be_valid
      expect(description.errors[:wikipedia_id]).to include("can't be blank")
    end
  end

  context "#wiki_url" do
    it "builds the wikipedia curid URL from wikipedia_id" do
      description = build_description(wikipedia_id: 24_390)
      expect(description.wiki_url).to eq("https://en.wikipedia.org/wiki/index.html?curid=24390")
    end

    it "reflects the record's actual wikipedia_id" do
      description = build_description(wikipedia_id: 999)
      expect(description.wiki_url).to eq("https://en.wikipedia.org/wiki/index.html?curid=999")
    end
  end
end
