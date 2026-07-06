# frozen_string_literal: true

require "rails_helper"

# PathogenListHelper is a bag of frozen prompt/message templates used by the
# pathogen-list update rake flow. We verify the templates interpolate correctly
# (right number of %s slots) and are frozen.
RSpec.describe PathogenListHelper do
  it "freezes every string constant" do
    described_class.constants.each do |const_name|
      value = described_class.const_get(const_name)
      expect(value).to be_frozen, "expected #{const_name} to be frozen"
    end
  end

  describe "single-slot templates" do
    it "CONFIRM_VERSION_CREATION interpolates the version" do
      expect(format(described_class::CONFIRM_VERSION_CREATION, "0.1.0"))
        .to eq("Version 0.1.0 not found. Do you want to create a new version? (yes/NO)")
    end

    it "CONFIRM_LIST_VERSION_OVERWRITE interpolates the version" do
      expect(format(described_class::CONFIRM_LIST_VERSION_OVERWRITE, "1.2.3"))
        .to include("Version 1.2.3 already exists")
    end

    it "CITATION_NOT_FOUND interpolates the source" do
      expect(format(described_class::CITATION_NOT_FOUND, "src-9"))
        .to eq("Citation not found: [source=src-9]")
    end

    it "PROMPT_CITATION_CREATE interpolates the footnote" do
      expect(format(described_class::PROMPT_CITATION_CREATE, "fn"))
        .to include("[footnote=fn]")
    end
  end

  describe "multi-slot templates" do
    it "TAXON_NOT_FOUND_TEMPLATE interpolates pathogen + taxID" do
      expect(format(described_class::TAXON_NOT_FOUND_TEMPLATE, "E. coli", 562))
        .to eq("Taxon not found: [pathogen=E. coli taxID=562]")
    end

    it "UPDATE_PROCESS_COMPLETE_TEMPLATE interpolates version, pathogen count, citation count" do
      expect(format(described_class::UPDATE_PROCESS_COMPLETE_TEMPLATE, "0.1.0", 12, 3))
        .to eq("Process complete: global pathogen list 0.1.0 created with 12 pathogens and 3 citations")
    end

    it "NOT_FOUND_PATHOGENS_TEMPLATE interpolates count + tax_id list" do
      expect(format(described_class::NOT_FOUND_PATHOGENS_TEMPLATE, 2, "[1, 2]"))
        .to include("2 pathogens")
    end
  end

  describe "static prompts" do
    it "exposes the plain-string prompts" do
      expect(described_class::UPDATE_PROCESS_FAILED).to eq("Update pathogen list failed")
      expect(described_class::USER_CANCELLED).to eq("User cancelled pathogen list update")
      expect(described_class::PROMPT_FOR_LIST_VERSION).to include("pathogen list version")
    end
  end
end
