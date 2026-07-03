# CZID-285 — Layer 3 identity-verification + export-screening clearance record.
#
# One row per clearance event: the outcome of running a user's identity through an IDV/KYC provider
# (verification_status) AND against denied/restricted-party lists (screening_result). This is the
# app-layer companion to the Layer-2 edge IP-intel decision; it answers "is this verified person
# actually entitled to export-controlled access?" (design doc Layer 3 / EXPORT-CONTROL-LAYER3-DESIGN.md).
#
# APPEND-ONLY by intent (mirrors CZID-330 ExportControlAttestation): never update or delete a row; a
# re-clearance (new attempt, refreshed verification, re-screen) creates a NEW row so the full evidence
# history is retained. Retention is counsel-owned (CZID-331); do NOT add a destroy path — the User
# association is dependent: :restrict_with_exception, not :destroy.
class CreateExportControlClearances < ActiveRecord::Migration[7.0]
  def change
    create_table :export_control_clearances do |t|
      t.bigint  :user_id, null: false

      # IDV / KYC outcome — verified / failed / pending. String (not boolean) so the record is explicit
      # and fail-closed: anything other than the exact "verified" string is NOT a pass (CZID-285).
      t.string  :verification_status, null: false
      # Denied/restricted-party screening outcome — clear / hit / pending. Only the exact "clear" string
      # is a pass; "hit" (a sanctions/denied-party match) and "pending" both DENY (counsel owns the
      # legally-correct hit response — TODO(counsel)).
      t.string  :screening_result, null: false

      # Which provider produced this clearance (e.g. the IDV vendor + the screening vendor). Recorded for
      # the evidence trail; the FINAL vendors are counsel/procurement-chosen (TODO(counsel/vendor)).
      t.string  :idv_provider
      t.string  :screening_provider

      # Opaque references to the provider-side evidence (IDV inquiry id, screening case id, document
      # hashes). We store REFERENCES, not raw PII/documents — the sensitive artifacts live with the
      # vendor under their DPA (TODO(counsel): confirm what, if anything, may be persisted here).
      t.string  :idv_evidence_ref
      t.string  :screening_evidence_ref

      # The version of the clearance policy/ruleset the user was cleared under. Bumping this (in lockstep
      # with a policy change) forces re-clearance, exactly like ExportControlAttestation::CURRENT_VERSION.
      t.string  :clearance_version, null: false

      # Source IP + edge-seen country captured at clearance time — part of the compliance record
      # (design doc §6: every access decision logs the IP).
      t.string  :ip_address
      t.string  :viewer_country
      t.string  :user_agent, limit: 1024

      t.datetime :created_at, precision: 6, null: false
      # No updated_at: rows are append-only / immutable by intent (see class comment).
    end

    add_index :export_control_clearances, :user_id
    # Fast "does this user have a current, affirmatively-passed clearance for version X?" lookup for the
    # gate (CZID-285): verified IDV AND clear screening, current version.
    add_index :export_control_clearances,
              [:user_id, :clearance_version, :verification_status, :screening_result],
              name: "idx_export_clearance_user_version_status"
  end
end
