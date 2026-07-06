require "rails_helper"

RSpec.describe UsersHelper, type: :helper do
  describe ".generate_random_password" do
    it "produces a password satisfying the complexity policy (upper/lower/digit/symbol)" do
      pw = UsersHelper.generate_random_password
      expect(pw).to match(/[A-Z]/)
      expect(pw).to match(/[a-z]/)
      expect(pw).to match(/[0-9]/)
      expect(pw).to match(/[^A-Za-z0-9]/)
    end

    it "squeezes out consecutive repeated characters" do
      pw = UsersHelper.generate_random_password
      expect(pw).not_to match(/(.)\1/)
    end

    it "returns a different value on each call" do
      expect(UsersHelper.generate_random_password).not_to eq(UsersHelper.generate_random_password)
    end
  end

  describe ".calculate_quarter_year" do
    it "labels a January date as Q1" do
      travel_to(Date.new(2023, 1, 15)) do
        expect(UsersHelper.calculate_quarter_year).to eq("Q1 2023")
      end
    end

    it "labels a March date as Q1 (boundary of first quarter)" do
      travel_to(Date.new(2023, 3, 31)) do
        expect(UsersHelper.calculate_quarter_year).to eq("Q1 2023")
      end
    end

    it "labels an April date as Q2" do
      travel_to(Date.new(2023, 4, 1)) do
        expect(UsersHelper.calculate_quarter_year).to eq("Q2 2023")
      end
    end

    it "labels a December date as Q4" do
      travel_to(Date.new(2024, 12, 25)) do
        expect(UsersHelper.calculate_quarter_year).to eq("Q4 2024")
      end
    end
  end

  describe ".send_profile_form_to_airtable" do
    let(:user) { create(:user) }

    it "posts a fully-populated payload to Airtable when all params are provided" do
      captured_table = nil
      captured_json = nil
      allow(MetricUtil).to receive(:post_to_airtable) do |table, json|
        captured_table = table
        captured_json = json
      end

      params = {
        profile_form_version: "v2",
        first_name: "Ada",
        last_name: "Lovelace",
        ror_institution: "Institute",
        ror_id: "ror-1",
        country: "UK",
        world_bank_income: "High",
        czid_usecase: ["research"],
        expertise_level: "expert",
        referral_source: ["colleague"],
        newsletter_consent: true,
      }

      UsersHelper.send_profile_form_to_airtable(user, params)

      expect(captured_table).to eq("CZ ID User Profiles")
      payload = JSON.parse(captured_json)
      fields = payload["fields"]
      expect(fields["user_id"]).to eq(user.id)
      expect(fields["email"]).to eq(user.email)
      expect(fields["first_name"]).to eq("Ada")
      expect(fields["czid_usecase"]).to eq(["research"])
      expect(fields["newsletter_consent"]).to be(true)
      expect(payload["typecast"]).to be(true)
    end

    it "falls back to user attributes and empty defaults when params are blank" do
      captured_json = nil
      allow(MetricUtil).to receive(:post_to_airtable) { |_table, json| captured_json = json }

      UsersHelper.send_profile_form_to_airtable(user, {})

      fields = JSON.parse(captured_json)["fields"]
      expect(fields["survey_version"]).to eq("")
      expect(fields["ror_institution"]).to eq("")
      expect(fields["czid_usecase"]).to eq([])
      expect(fields["referral_source"]).to eq([])
      expect(fields["newsletter_consent"]).to be(false)
    end
  end
end
