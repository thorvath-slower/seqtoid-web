# CZID-597 (Export-control Layer 3 / #285) -- Descartes Visual Compliance restricted-party SCREENING
# evidence table. One row per party per SearchEntity screen. ADDITIVE ONLY -- no existing table is
# touched. This is inert until the Descartes ScreeningService (CZID-596) is enabled behind its
# OFF-by-default flag; no code writes here until then.
#
# APPEND-ONLY by intent (mirrors ExportControlClearance / ExportControlAttestation): a re-screen creates a
# NEW row so the full evidence history is retained. Retention + hit-handling policy are counsel-owned
# (design doc Layer 3). We store a REFERENCE to the raw vendor response, not the raw list data / PII.
class CreateScreeningResults < ActiveRecord::Migration[7.0]
  def change
    # if_not_exists keeps the migration self-healing if a prior run half-applied (same pattern as #533).
    create_table :screening_results, if_not_exists: true do |t|
      # OUR reference to the screened subject (a user id, sample id, etc). String so the table is
      # subject-agnostic -- the gate point (onboarding vs submission vs download) is counsel-owned and not
      # yet fixed, so we do NOT couple this row to a single AR model.
      t.string :subject_ref, null: false
      # Optional subject class name (e.g. "User", "Sample") to disambiguate subject_ref when set.
      t.string :subject_type

      # soptionalid -- the correlation id WE send to Descartes (SearchEntity soptionalid) so a returned
      # verdict / Incident Manager record can be tied back to this screen. Compliance Manager requires this
      # to be "0" or a TABLE-KEYED reference (this row's own id), NOT a random GUID -- the ScreeningService
      # mints it from this record's id.
      t.string :soptionalid

      # transstatus -- the PRIMARY machine-readable release/hold signal from Descartes: "Passed" or
      # "On Hold-RPS". This is Descartes' own on-hold determination for the transaction and is what the
      # gate keys off FIRST. Fail-closed: anything that is not exactly "Passed" holds (see the model).
      t.string :transstatus

      # The mapped Descartes alert level (SEVERITY detail, secondary to transstatus): nomatch / wl / al /
      # yellow / red / double_red / triple_red -- derived from smaxalert (_Y/_R/DR/TR/RC/WL/AL/empty).
      # Recorded so the compliance officer sees how severe the match is; the allow/hold decision is
      # transstatus-primary, not letter-primary (ScreeningResult::ALERT_LEVELS).
      t.string :alert_level, null: false
      # Independent Descartes Risk Country flag for the scountry input: 0 not-risk / 1 risk / 2 caution /
      # 3 invalid-code. Set even with no name/entity match. Nullable.
      t.integer :risk_country
      # Which RPS list(s) the screen ran against (Export / Munitions / GSA / ...). Counsel owns the list
      # selection; recorded here as evidence of what was screened.
      t.string :list

      # sdistributedid -- the Descartes audit-history record id returned by the screen (per search). The
      # correlation key the resolution poller (CZID-598 IMTimeStampSearch) matches verdicts back on.
      t.string :sdistributedid

      # Descartes Incident Manager record id, set ONLY on a real hit that a human compliance officer must
      # adjudicate. Nullable: a clean screen (nomatch) has no incident; populated later by the poller.
      t.string :incident_id

      # The provider that produced this row (default "descartes"), for the evidence trail.
      t.string :provider

      # When the screen ran.
      t.datetime :screened_at, null: false

      # Opaque REFERENCE to the raw vendor response (e.g. an s3 key or a log correlation id). We do NOT
      # persist the raw restricted-party list payload here -- only a pointer, per the DPA posture.
      t.string :raw_response_ref

      t.datetime :created_at, precision: 6, null: false
      # No updated_at: rows are append-only / immutable by intent (see class comment).
    end

    # "latest result for this subject" lookups (the ScreeningResult.latest_for scope).
    add_index :screening_results, [:subject_ref, :screened_at], if_not_exists: true
    add_index :screening_results, :incident_id, if_not_exists: true
  end
end
