require 'rails_helper'

# CZID-330 — the attestation record + the gate's fail-closed "is this user cleared?" logic.
RSpec.describe ExportControlAttestation, type: :model do
  let(:user) { create(:user) }
  let(:version) { ExportControlAttestation::CURRENT_VERSION }

  describe "validations" do
    it "requires a known decision" do
      rec = described_class.new(user: user, decision: "maybe", attestation_version: version)
      expect(rec).not_to be_valid
      expect(rec.errors[:decision]).to be_present
    end

    it "requires an attestation_version" do
      rec = described_class.new(user: user, decision: described_class::DECISION_ACCEPTED, attestation_version: nil)
      expect(rec).not_to be_valid
    end

    it "accepts a well-formed accepted record" do
      rec = described_class.new(user: user, decision: described_class::DECISION_ACCEPTED, attestation_version: version)
      expect(rec).to be_valid
    end
  end

  describe ".current_attestation_satisfied?" do
    it "is FALSE for a nil user (fail-closed)" do
      expect(described_class.current_attestation_satisfied?(nil)).to be(false)
    end

    it "is FALSE when the user has never attested (fail-closed)" do
      expect(described_class.current_attestation_satisfied?(user)).to be(false)
    end

    it "is FALSE when the user only DECLINED (fail-closed)" do
      create(:export_control_attestation, user: user, decision: described_class::DECISION_DECLINED)
      expect(described_class.current_attestation_satisfied?(user)).to be(false)
    end

    it "is FALSE when the accepted record is for a DIFFERENT (stale) version (fail-closed)" do
      create(:export_control_attestation, user: user, decision: described_class::DECISION_ACCEPTED, attestation_version: "v0-old")
      expect(described_class.current_attestation_satisfied?(user)).to be(false)
    end

    it "is TRUE only when the user accepted the CURRENT version" do
      create(:export_control_attestation, user: user, decision: described_class::DECISION_ACCEPTED, attestation_version: version)
      expect(described_class.current_attestation_satisfied?(user)).to be(true)
    end
  end

  describe ".latest_decision_declined?" do
    it "is false when there is no record" do
      expect(described_class.latest_decision_declined?(user)).to be(false)
    end

    it "is true when the latest record for the current version is a decline" do
      create(:export_control_attestation, user: user, decision: described_class::DECISION_DECLINED, created_at: 2.hours.ago)
      expect(described_class.latest_decision_declined?(user)).to be(true)
    end

    it "is false once a later ACCEPT supersedes an earlier decline" do
      create(:export_control_attestation, user: user, decision: described_class::DECISION_DECLINED, created_at: 2.hours.ago)
      create(:export_control_attestation, user: user, decision: described_class::DECISION_ACCEPTED, created_at: 1.hour.ago)
      expect(described_class.latest_decision_declined?(user)).to be(false)
      expect(described_class.current_attestation_satisfied?(user)).to be(true)
    end
  end
end
