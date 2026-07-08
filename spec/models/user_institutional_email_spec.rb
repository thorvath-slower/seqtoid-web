require 'rails_helper'

# CZID-523 -- institutional email domain allowlist enforcement on the User model.
describe User, type: :model do
  def configure_allowlist(domains)
    AppConfigHelper.set_json_app_config(AppConfig::ALLOWED_EMAIL_DOMAINS, domains)
  end

  context "#institutional_email?" do
    let(:user) { build(:user, email: "researcher@ucsf.edu") }

    it "is true when no allowlist is configured (enforcement disabled)" do
      expect(User.allowed_email_domains).to eq([])
      expect(user.institutional_email?).to be(true)
    end

    it "is true for an exact domain match" do
      configure_allowlist(["ucsf.edu"])
      expect(user.institutional_email?).to be(true)
    end

    it "is true for a subdomain of an approved domain" do
      configure_allowlist(["ucsf.edu"])
      subdomain_user = build(:user, email: "person@lab.ucsf.edu")
      expect(subdomain_user.institutional_email?).to be(true)
    end

    it "is false for a non-approved domain" do
      configure_allowlist(["ucsf.edu"])
      other = build(:user, email: "person@gmail.com")
      expect(other.institutional_email?).to be(false)
    end

    it "matches case-insensitively against a mixed-case allowlist entry" do
      configure_allowlist(["UCSF.EDU"])
      expect(user.institutional_email?).to be(true)
    end

    it "does not treat a suffix collision as a subdomain match" do
      configure_allowlist(["ucsf.edu"])
      spoof = build(:user, email: "person@notucsf.edu")
      expect(spoof.institutional_email?).to be(false)
    end
  end

  context ".allowed_email_domains" do
    it "reads and normalizes the AppConfig JSON list" do
      configure_allowlist([" UCSF.edu ", "@chanzuckerberg.com", "ucsf.edu", ""])
      expect(User.allowed_email_domains).to contain_exactly("ucsf.edu", "chanzuckerberg.com")
    end

    it "falls back to the ALLOWED_EMAIL_DOMAINS env var when AppConfig is unset" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("ALLOWED_EMAIL_DOMAINS").and_return("ucsf.edu, chanzuckerberg.com")
      expect(User.allowed_email_domains).to contain_exactly("ucsf.edu", "chanzuckerberg.com")
    end
  end

  context "validation on save" do
    it "accepts any domain when enforcement is disabled" do
      expect(build(:user, email: "anyone@example.com")).to be_valid
    end

    it "rejects a non-institutional email when an allowlist is set" do
      configure_allowlist(["ucsf.edu"])
      user = build(:user, email: "anyone@example.com")
      expect(user).not_to be_valid
      expect(user.errors[:email].join).to include("approved institutional email domains")
    end

    it "accepts an institutional email when an allowlist is set" do
      configure_allowlist(["ucsf.edu"])
      expect(build(:user, email: "researcher@ucsf.edu")).to be_valid
    end

    it "does not re-validate the domain on an unrelated update to an existing record" do
      configure_allowlist(["ucsf.edu"])
      user = create(:user, email: "researcher@ucsf.edu")
      configure_allowlist(["chanzuckerberg.com"]) # tighten after creation
      user.name = "New Name"
      expect(user.save).to be(true)
    end
  end
end
