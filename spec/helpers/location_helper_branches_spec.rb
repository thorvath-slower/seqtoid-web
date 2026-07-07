# frozen_string_literal: true

require "rails_helper"

# Coverage Wave 3: branch sweep for LocationHelper. These target the
# conditional OPPOSITE branches (nil coords, no geo match, non-array grouping
# keys, name-dedup then-branch, truncate fallbacks) that line-level specs leave
# untaken. Spec-only, no app changes.
RSpec.describe LocationHelper do
  describe ".adapt_location_iq_response" do
    it "falls through to the empty geo_level when nothing matches and nils absent coords" do
      body = {
        "address" => { "country_code" => "zz" },
        "type" => "river",
        "display_name" => "Somewhere",
        # no lat / lon keys -> the ternary else (nil) branch
        "osm_id" => nil,
      }

      loc = described_class.adapt_location_iq_response(body)

      expect(loc[:geo_level]).to eq("")
      expect(loc[:lat]).to be_nil
      expect(loc[:lng]).to be_nil
      expect(loc[:osm_id]).to eq(0)
      expect(loc[:osm_type]).to eq("")
      expect(loc[:country_code]).to eq("zz")
    end

    it "rounds present coordinates (the truthy ternary branch)" do
      body = {
        "address" => { "country_code" => "us" },
        "type" => "city",
        "display_name" => "Place",
        "lat" => "12.34567",
        "lon" => "-98.76543",
      }

      loc = described_class.adapt_location_iq_response(body)

      expect(loc[:lat]).to eq(12.35)
      expect(loc[:lng]).to eq(-98.77)
    end
  end

  describe ".truncate_name" do
    it "returns short names unchanged (the size guard else)" do
      expect(described_class.truncate_name("Short, Name")).to eq("Short, Name")
    end

    it "returns nil unchanged when given nil (the nil guard)" do
      expect(described_class.truncate_name(nil)).to be_nil
    end

    it "keeps first two + last two parts when that fits under the max" do
      long = (["A" * 40] + ["B", "C", "D", "E"]).join(", ")
      # >= 4 parts, first-two-plus-last-two still too long -> inner then-branch
      result = described_class.truncate_name(long)
      expect(result).to include("E")
    end

    it "does not truncate when there are fewer than four parts" do
      name = ("X" * 200) + ", " + ("Y" * 200)
      expect(described_class.truncate_name(name)).to eq(name)
    end
  end

  describe ".normalize_location_name" do
    it "dedupes a repeated 'A, A' name (the equal-parts then-branch)" do
      expect(described_class.normalize_location_name("Cambodia, Cambodia", Location::COUNTRY_LEVEL))
        .to eq("Cambodia")
    end

    it "leaves distinct comma parts intact (the not-equal else)" do
      expect(described_class.normalize_location_name("Phnom Penh, Cambodia", Location::COUNTRY_LEVEL))
        .to eq("Phnom Penh, Cambodia")
    end

    it "returns the name untouched when it has no comma" do
      expect(described_class.normalize_location_name("Cambodia", Location::COUNTRY_LEVEL))
        .to eq("Cambodia")
    end
  end

  describe ".sanitize_name" do
    it "strips injection-prone characters" do
      expect(described_class.sanitize_name("a;b%c<d>e/f?g\\h")).to eq("abcdefgh")
    end
  end
end
