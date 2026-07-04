# CZID-330 — the persisted export-control / Terms-of-Use attestation record + the gate's source of
# truth for "is this user cleared to proceed?".
#
# One row per attestation event. Rows are APPEND-ONLY (see the migration) — a re-attestation creates a
# new row, so the full history is retained as compliance evidence (design doc §6).
#
# TODO(counsel): the attestation TEXT itself and its version cadence are counsel-owned. This model only
# stores which version a user agreed to; the copy lives in the view (also TODO(counsel)).
class ExportControlAttestation < ApplicationRecord
  belongs_to :user

  DECISION_ACCEPTED = "accepted".freeze
  DECISION_DECLINED = "declined".freeze
  DECISIONS = [DECISION_ACCEPTED, DECISION_DECLINED].freeze

  # The CURRENT attestation text version. Bump this (in lockstep with the counsel-approved copy in the
  # view) to force every user to re-attest. Kept as a constant so the gate and the record agree.
  # TODO(counsel): own this value + the copy it points at.
  CURRENT_VERSION = "v1-draft".freeze

  validates :decision, inclusion: { in: DECISIONS }
  validates :attestation_version, presence: true
  validates :user_id, presence: true

  scope :accepted, -> { where(decision: DECISION_ACCEPTED) }
  scope :for_version, ->(v) { where(attestation_version: v) }

  # The gate's core question: has this user accepted the CURRENT attestation version?
  # Fail-closed by construction — anything other than a positive "yes, accepted, current version"
  # means the gate has NOT been satisfied and the user must attest (CZID-330).
  def self.current_attestation_satisfied?(user, version: CURRENT_VERSION)
    return false if user.nil?

    accepted.for_version(version).where(user_id: user.id).exists?
  end

  # Whether the user's LATEST attestation for the current version was a decline (drives the deny UX
  # vs. the first-time attest prompt). A decline is not terminal for the record — the user could later
  # accept — but while their latest state is declined they are denied.
  def self.latest_decision_declined?(user, version: CURRENT_VERSION)
    return false if user.nil?

    latest = for_version(version).where(user_id: user.id).order(created_at: :desc).first
    latest.present? && latest.decision == DECISION_DECLINED
  end
end
