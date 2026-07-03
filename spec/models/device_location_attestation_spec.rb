require 'rails_helper'

# CZID-286 — the Layer 3 device/location attestation record + the gate's fail-closed predicate. Allow is
# reachable ONLY on a verified attestation for the current policy version.
RSpec.describe DeviceLocationAttestation, type: :model do
  let(:user) { create(:user) }

  describe "validations" do
    it "requires a known attestation_status" do
      rec = described_class.new(user: user, attestation_status: "maybe",
                                attestation_policy_version: described_class::CURRENT_VERSION)
      expect(rec).not_to be_valid
      expect(rec.errors[:attestation_status]).to be_present
    end

    it "requires a policy version" do
      rec = described_class.new(user: user, attestation_status: described_class::STATUS_VERIFIED,
                                attestation_policy_version: nil)
      expect(rec).not_to be_valid
    end
  end

  describe ".current_attestation_satisfied? (fail-closed deny matrix)" do
    it "is FALSE for a nil user" do
      expect(described_class.current_attestation_satisfied?(nil)).to be(false)
    end

    it "is FALSE when there is no record" do
      expect(described_class.current_attestation_satisfied?(user)).to be(false)
    end

    it "is FALSE when the attestation is PENDING" do
      create(:device_location_attestation, :pending, user: user)
      expect(described_class.current_attestation_satisfied?(user)).to be(false)
    end

    it "is FALSE when the attestation FAILED (spoofed)" do
      create(:device_location_attestation, :failed, user: user)
      expect(described_class.current_attestation_satisfied?(user)).to be(false)
    end

    it "is FALSE when the verified record is for a STALE policy version" do
      create(:device_location_attestation, :stale_version, user: user)
      expect(described_class.current_attestation_satisfied?(user)).to be(false)
    end

    it "is TRUE only when verified for the current policy version" do
      create(:device_location_attestation, user: user)
      expect(described_class.current_attestation_satisfied?(user)).to be(true)
    end
  end
end
