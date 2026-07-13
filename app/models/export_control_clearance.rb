# CZID-285 — Layer 3 identity-verification + export-screening clearance record + the gate's source of
# truth for "is this user affirmatively cleared for export-controlled access?".
#
# One row per clearance event. Rows are APPEND-ONLY (see the migration) — a re-clearance creates a new
# row, so the full history is retained as compliance evidence. This mirrors CZID-330
# ExportControlAttestation exactly (record + fail-closed class predicate the gate consults).
#
# FAIL-CLOSED by construction (design doc: zero-tolerance). The ONLY way to be "cleared" is an
# affirmatively-passed clearance for the CURRENT version: verification_status == "verified" AND
# screening_result == "clear". Every other state — nil user, no record, pending, failed, screening hit,
# stale version — means NOT cleared. There is no allow-on-uncertainty path here.
#
# TODO(counsel/vendor): the IDV vendor, the screening vendor + the applicable lists + the legally-correct
# response to a screening HIT, the data-classification that decides WHEN a clearance is required, and the
# clearance policy version cadence are all counsel/procurement-owned. This model only records outcomes.
class ExportControlClearance < ApplicationRecord
  belongs_to :user

  # --- Identity-verification (IDV/KYC) outcomes ---
  VERIFICATION_VERIFIED = "verified".freeze
  VERIFICATION_FAILED   = "failed".freeze
  VERIFICATION_PENDING  = "pending".freeze
  VERIFICATION_STATUSES = [VERIFICATION_VERIFIED, VERIFICATION_FAILED, VERIFICATION_PENDING].freeze

  # --- Denied/restricted-party screening outcomes ---
  SCREENING_CLEAR   = "clear".freeze
  SCREENING_HIT     = "hit".freeze
  SCREENING_PENDING = "pending".freeze
  SCREENING_RESULTS = [SCREENING_CLEAR, SCREENING_HIT, SCREENING_PENDING].freeze

  # The CURRENT clearance policy version. Bump this (in lockstep with a policy change) to force every
  # user to re-clear. Kept as a constant so the gate and the record agree.
  # TODO(counsel): own this value + the policy it points at.
  CURRENT_VERSION = "v1-draft".freeze

  validates :verification_status, inclusion: { in: VERIFICATION_STATUSES }
  validates :screening_result, inclusion: { in: SCREENING_RESULTS }
  validates :clearance_version, presence: true
  validates :user_id, presence: true

  # A row is "passed" only if BOTH sub-checks affirmatively passed. Used by the scope + the predicate.
  scope :passed, lambda {
    where(verification_status: VERIFICATION_VERIFIED, screening_result: SCREENING_CLEAR)
  }
  scope :for_version, ->(v) { where(clearance_version: v) }

  # The gate's core question: does this user have a current, affirmatively-passed clearance?
  # Fail-closed — anything other than "yes, verified AND clear, current version" returns false.
  def self.current_clearance_satisfied?(user, version: CURRENT_VERSION)
    return false if user.nil?

    passed.for_version(version).where(user_id: user.id).exists?
  end

  # Instance-level convenience mirroring the class predicate (a single row's pass/fail).
  def passed?
    verification_status == VERIFICATION_VERIFIED && screening_result == SCREENING_CLEAR
  end
end
