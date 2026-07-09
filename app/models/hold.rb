# CZID-597 (Export-control Layer 3 / #285) -- a restricted-party HOLD on a subject/item, placed when a
# Descartes screen HITS (or the screen fails-closed on error/timeout). Released only after a human
# compliance officer adjudicates. Written by the ScreeningService (CZID-596); inert until that service is
# enabled behind its OFF-by-default flag.
class Hold < ApplicationRecord
  # Why a hold was placed. Kept explicit so the record is self-describing.
  REASON_SCREENING_HIT = "screening_hit".freeze  # a real alert-level match
  REASON_SCREENING_ERROR = "screening_error".freeze  # fail-closed: vendor error/timeout/misconfig
  REASONS = [REASON_SCREENING_HIT, REASON_SCREENING_ERROR].freeze

  # The screen that triggered the hold. Optional: a fail-closed error may have no persisted screen row.
  belongs_to :screening_result, optional: true

  validates :subject_ref, presence: true
  validates :reason, inclusion: { in: REASONS }

  # Still-in-force holds (not yet released), and the per-subject filter.
  scope :active, -> { where(released_at: nil) }
  scope :released, -> { where.not(released_at: nil) }
  scope :for_subject, ->(ref) { where(subject_ref: ref) }

  # True while the hold is in force.
  def active?
    released_at.nil?
  end

  # Mark the hold released (adjudicated). Idempotent -- keeps the first release timestamp.
  def release!(at: Time.current)
    return true unless active?

    update!(released_at: at)
  end
end
