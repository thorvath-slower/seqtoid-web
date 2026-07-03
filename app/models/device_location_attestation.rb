# CZID-286 — Layer 3 device / location attestation record (SERVER-SIDE) + the gate's source of truth for
# "did this user's device produce a currently-valid, verified location attestation?".
#
# One row per verified attestation event. Rows are APPEND-ONLY (see the migration). Mirrors CZID-330 /
# CZID-285: record + fail-closed class predicate.
#
# FAIL-CLOSED: the ONLY "verified" state is attestation_status == "verified" for the CURRENT policy
# version. A failed/expired/spoofed/malformed token, a pending attestation, a stale version, or no record
# all mean NOT verified. There is no allow-on-uncertainty path.
#
# TODO(counsel/vendor): the device-location vendor (GeoComply PinPoint the reference shape), its DPA,
# consent, precise-location retention, and WHICH flows require device attestation are counsel/product-owned.
class DeviceLocationAttestation < ApplicationRecord
  belongs_to :user

  STATUS_VERIFIED = "verified".freeze
  STATUS_FAILED   = "failed".freeze
  STATUS_PENDING  = "pending".freeze
  STATUSES = [STATUS_VERIFIED, STATUS_FAILED, STATUS_PENDING].freeze

  # Structured, non-authoritative failure reasons (evidence only; never drive an allow).
  FAILURE_INVALID_SIGNATURE = "invalid_signature".freeze
  FAILURE_EXPIRED           = "expired".freeze
  FAILURE_SPOOFED           = "spoofed".freeze
  FAILURE_MALFORMED         = "malformed".freeze
  FAILURE_PROVIDER_ERROR    = "provider_error".freeze

  # The CURRENT device-attestation policy version. Bump to force re-attestation.
  # TODO(counsel): own this value + the policy it points at.
  CURRENT_VERSION = "v1-draft".freeze

  validates :attestation_status, inclusion: { in: STATUSES }
  validates :attestation_policy_version, presence: true
  validates :user_id, presence: true

  scope :verified, -> { where(attestation_status: STATUS_VERIFIED) }
  scope :for_version, ->(v) { where(attestation_policy_version: v) }

  # The gate's core question: does this user have a current, VERIFIED device-location attestation?
  # Fail-closed — anything other than "yes, verified, current version" returns false.
  def self.current_attestation_satisfied?(user, version: CURRENT_VERSION)
    return false if user.nil?

    verified.for_version(version).where(user_id: user.id).exists?
  end
end
