require 'rails_helper'

# CZID-285 — the Layer 3 clearance record + the gate's fail-closed "is this user cleared?" predicate.
# The allow path is reachable ONLY on verified IDV AND clear screening for the current version; every
# other state DENIES.
RSpec.describe ExportControlClearance, type: :model do
  let(:user) { create(:user) }
  let(:version) { ExportControlClearance::CURRENT_VERSION }

  describe "validations" do
    it "requires a known verification_status" do
      rec = described_class.new(user: user, verification_status: "maybe",
                                screening_result: described_class::SCREENING_CLEAR, clearance_version: version)
      expect(rec).not_to be_valid
      expect(rec.errors[:verification_status]).to be_present
    end

    it "requires a known screening_result" do
      rec = described_class.new(user: user, verification_status: described_class::VERIFICATION_VERIFIED,
                                screening_result: "unsure", clearance_version: version)
      expect(rec).not_to be_valid
      expect(rec.errors[:screening_result]).to be_present
    end

    it "requires a clearance_version" do
      rec = described_class.new(user: user, verification_status: described_class::VERIFICATION_VERIFIED,
                                screening_result: described_class::SCREENING_CLEAR, clearance_version: nil)
      expect(rec).not_to be_valid
    end

    it "accepts a well-formed passed record" do
      rec = described_class.new(user: user, verification_status: described_class::VERIFICATION_VERIFIED,
                                screening_result: described_class::SCREENING_CLEAR, clearance_version: version)
      expect(rec).to be_valid
    end
  end

  describe ".current_clearance_satisfied? (fail-closed deny matrix)" do
    it "is FALSE for a nil user" do
      expect(described_class.current_clearance_satisfied?(nil)).to be(false)
    end

    it "is FALSE when the user has no clearance record" do
      expect(described_class.current_clearance_satisfied?(user)).to be(false)
    end

    it "is FALSE when verification is PENDING (screening clear)" do
      create(:export_control_clearance, :verification_pending, user: user)
      expect(described_class.current_clearance_satisfied?(user)).to be(false)
    end

    it "is FALSE when verification FAILED (screening clear)" do
      create(:export_control_clearance, :verification_failed, user: user)
      expect(described_class.current_clearance_satisfied?(user)).to be(false)
    end

    it "is FALSE when screening is a HIT (verification verified)" do
      create(:export_control_clearance, :screening_hit, user: user)
      expect(described_class.current_clearance_satisfied?(user)).to be(false)
    end

    it "is FALSE when screening is PENDING (verification verified)" do
      create(:export_control_clearance, :screening_pending, user: user)
      expect(described_class.current_clearance_satisfied?(user)).to be(false)
    end

    it "is FALSE when the passed record is for a STALE version" do
      create(:export_control_clearance, :stale_version, user: user)
      expect(described_class.current_clearance_satisfied?(user)).to be(false)
    end

    it "is TRUE only when verified AND clear for the current version" do
      create(:export_control_clearance, user: user)
      expect(described_class.current_clearance_satisfied?(user)).to be(true)
    end
  end

  describe "#passed?" do
    it "is true only for verified + clear" do
      expect(build(:export_control_clearance).passed?).to be(true)
      expect(build(:export_control_clearance, :screening_hit).passed?).to be(false)
      expect(build(:export_control_clearance, :verification_failed).passed?).to be(false)
    end
  end
end
