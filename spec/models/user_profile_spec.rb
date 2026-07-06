require 'rails_helper'

RSpec.describe UserProfile, type: :model do
  let(:user) { create(:user) }

  def build_profile(**attrs)
    UserProfile.new({ user: user }.merge(attrs))
  end

  context "associations" do
    it "belongs to a user" do
      profile = build_profile
      expect(profile.user).to eq(user)
    end

    it "is invalid without a user" do
      profile = UserProfile.new(user: nil)
      expect(profile).not_to be_valid
      expect(profile.errors[:user]).to be_present
    end
  end

  context "profile_form_version validation" do
    it "allows a nil profile_form_version" do
      profile = build_profile(profile_form_version: nil)
      expect(profile).to be_valid
    end

    it "allows an integer profile_form_version" do
      profile = build_profile(profile_form_version: 2)
      expect(profile).to be_valid
    end

    it "rejects a non-integer profile_form_version" do
      profile = build_profile(profile_form_version: 1.5)
      expect(profile).not_to be_valid
      expect(profile.errors[:profile_form_version]).to be_present
    end
  end

  context "serialized array attributes" do
    it "round-trips czid_usecase as an array" do
      profile = build_profile(czid_usecase: ["research", "surveillance"])
      profile.save!
      expect(profile.reload.czid_usecase).to eq(["research", "surveillance"])
    end

    it "round-trips referral_source as an array" do
      profile = build_profile(referral_source: ["colleague"])
      profile.save!
      expect(profile.reload.referral_source).to eq(["colleague"])
    end
  end
end
