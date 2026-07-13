# CZID-330 — persisted export-control / Terms-of-Use attestation record.
#
# One row per attestation event (the user attesting they are not in / not acting for a blocked
# jurisdiction, or declining). This is the compliance evidence trail for the click-through gate — it is
# APPEND-ONLY by intent: never update or delete a row; a user who re-attests (e.g. a new attestation
# version) gets a NEW row, so the full history is retained. Retention is counsel-owned (see the
# EXPORT-CONTROL audit docs / CZID-331); do not add a destroy path.
class CreateExportControlAttestations < ActiveRecord::Migration[7.0]
  def change
    create_table :export_control_attestations do |t|
      t.bigint  :user_id, null: false
      # accepted / declined — the attestation outcome. String (not boolean) so the record is explicit
      # and extensible (e.g. a future "expired") without a data migration.
      t.string  :decision, null: false
      # The attestation TEXT VERSION the user was shown + agreed to. Legal copy is counsel-owned and
      # versioned; storing the version makes the record defensible ("this user agreed to v1 of the text").
      t.string  :attestation_version, null: false
      # The source IP captured at attestation time (request.remote_ip) — part of the compliance record
      # per design doc §6 (every access decision logs the IP).
      t.string  :ip_address
      # The country CloudFront/edge saw at attestation time, if forwarded (defense-in-depth evidence).
      t.string  :viewer_country
      # Free-form user agent for the evidence record.
      t.string  :user_agent, limit: 1024

      t.datetime :created_at, precision: 6, null: false
      # No updated_at: rows are append-only / immutable by intent (see class comment).
    end

    add_index :export_control_attestations, :user_id
    # Fast "does this user have a current accepted attestation for version X?" lookup for the gate.
    add_index :export_control_attestations, [:user_id, :attestation_version, :decision],
              name: "idx_export_attest_user_version_decision"
  end
end
