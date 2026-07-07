require 'rails_helper'

# Coverage Wave 2 (branch): user_spec.rb only touches allowed_feature_list + salt,
# leaving User's many small conditionals (upload gating, feature add/remove,
# biohub/czi domain checks, name splitting, login tracking, analytics PII) with
# untaken branches. These exercise both sides of each.
RSpec.describe User, type: :model do
  describe "#admin? / #role_name" do
    it "reports admin true and 'admin user' for a role-1 user" do
      admin = build(:admin)
      expect(admin.admin?).to eq(true)
      expect(admin.role_name).to eq("admin user")
    end

    it "reports admin false and 'non-admin user' for a regular user" do
      user = build(:user, role: User::ROLE_REGULAR_USER)
      expect(user.admin?).to eq(false)
      expect(user.role_name).to eq("non-admin user")
    end
  end

  describe "#allowed_feature?" do
    it "is true when the feature is in the allowed list and false otherwise" do
      user = build(:user, allowed_features: '["cool_feature"]')
      allow(AppConfigHelper).to receive(:get_json_app_config).and_return([])
      expect(user.allowed_feature?("cool_feature")).to eq(true)
      expect(user.allowed_feature?("missing_feature")).to eq(false)
    end
  end

  describe "#add_allowed_feature / #remove_allowed_feature" do
    before { allow(AppConfigHelper).to receive(:get_json_app_config).and_return([]) }

    it "adds a feature only when not already present" do
      user = create(:user, allowed_features: '[]')
      user.add_allowed_feature("f1")
      expect(user.reload.allowed_feature_list).to include("f1")
      # Adding again is a no-op (the `unless include?` false branch).
      expect(user).not_to receive(:update)
      user.add_allowed_feature("f1")
    end

    it "removes a feature only when present" do
      user = create(:user, allowed_features: '["f1"]')
      user.remove_allowed_feature("f1")
      expect(user.reload.allowed_feature_list).not_to include("f1")
      # Removing an absent feature is a no-op (the `if include?` false branch).
      expect(user).not_to receive(:update)
      user.remove_allowed_feature("f1")
    end
  end

  describe "#can_upload" do
    let(:admin) { build(:admin) }
    let(:user) { build(:user, allowed_features: '[]') }

    before { allow(AppConfigHelper).to receive(:get_json_app_config).and_return([]) }

    it "always allows an admin (early return true)" do
      expect(admin.can_upload("s3://anything/x")).to eq(true)
    end

    it "rejects an idseq-prefixed bucket" do
      expect(user.can_upload("s3://idseq-uploads/x")).to eq(false)
    end

    it "rejects a nil bucket (malformed path)" do
      expect(user.can_upload("s3:///")).to eq(false)
    end

    it "rejects a czbiohub bucket for a non-biohub user" do
      expect(user.can_upload("s3://czb-private/x")).to eq(false)
    end

    it "allows a czbiohub bucket for a biohub user" do
      biohub = build(:user, email: "person@czbiohub.org", allowed_features: '[]')
      expect(biohub.can_upload("s3://czbiohub-data/x")).to eq(true)
    end

    it "allows an ordinary bucket" do
      expect(user.can_upload("s3://my-lab-bucket/x")).to eq(true)
    end
  end

  describe "#biohub_user? / #czi_user?" do
    it "recognizes biohub and ucsf domains" do
      expect(build(:user, email: "a@czbiohub.org").biohub_user?).to eq(true)
      expect(build(:user, email: "a@ucsf.edu").biohub_user?).to eq(true)
      expect(build(:user, email: "a@gmail.com").biohub_user?).to eq(false)
    end

    it "recognizes czi domains including subdomains" do
      expect(build(:user, email: "a@chanzuckerberg.com").czi_user?).to eq(true)
      expect(build(:user, email: "a@sub.chanzuckerberg.com").czi_user?).to eq(true)
      expect(build(:user, email: "a@example.com").czi_user?).to eq(false)
    end
  end

  describe "#first_name / #last_name" do
    it "splits a full name" do
      user = build(:user, name: "Greg L. Dingle")
      expect(user.first_name).to eq("Greg L.")
      expect(user.last_name).to eq("Dingle")
    end

    it "returns nil for both when name is nil" do
      user = build(:user, name: nil)
      expect(user.first_name).to be_nil
      expect(user.last_name).to be_nil
    end
  end

  describe "#update_tracked_fields!" do
    it "returns early without touching fields for a new (unsaved) record" do
      user = build(:user)
      request = instance_double("ActionDispatch::Request", remote_ip: "1.2.3.4")
      user.update_tracked_fields!(request)
      # new_record? early-return: current_sign_in_at is never assigned.
      expect(user.current_sign_in_at).to be_nil
    end

    it "carries the previous sign-in over and increments the count for a persisted user" do
      user = create(:user, current_sign_in_at: nil, current_sign_in_ip: nil)
      request = instance_double("ActionDispatch::Request", remote_ip: "9.9.9.9")
      user.update_tracked_fields!(request)
      # old_current was nil -> last == new_current (the `||` right side).
      expect(user.current_sign_in_ip).to eq("9.9.9.9")
      expect(user.sign_in_count).to eq(1)
    end
  end

  describe "#traits_for_analytics" do
    it "omits PII by default and includes it when requested" do
      user = create(:user, name: "Ada Lovelace", institution: "Analytical Engine Co")
      allow(AppConfigHelper).to receive(:get_json_app_config).and_return([])

      non_pii = user.traits_for_analytics
      expect(non_pii).not_to have_key(:email)

      # bust the per-user cache so the include_pii branch actually runs.
      Rails.cache.clear
      pii = user.traits_for_analytics(include_pii: true)
      expect(pii[:email]).to eq(user.email)
      expect(pii[:firstName]).to eq("Ada")
    end
  end
end
