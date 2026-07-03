# CZID-286 — Layer 3 device / location attestation record (SERVER-SIDE).
#
# One row per verified device-attestation event. The client obtains a signed attestation token from the
# device-location vendor's SDK (GeoComply PinPoint the reference shape — TODO(vendor)); the server
# VERIFIES that token (signature + freshness + spoof flags) and persists the outcome here. This is the
# strongest true-origin signal (defeats residential-proxy / GPS spoofing that the network layer cannot
# see — EXPORT-CONTROL-LAYER3-DESIGN.md CZID-329).
#
# APPEND-ONLY by intent (mirrors CZID-330): never update or delete a row; a re-attestation creates a NEW
# row. Retention is counsel-owned (CZID-331); the User association is dependent: :restrict_with_exception.
#
# NOTE: precise location is SENSITIVE PII. We persist the VERIFICATION OUTCOME + coarse evidence refs,
# not raw precise coordinates. What (if anything) precise may be stored is counsel-owned (design doc §10
# item 7 — consent / location-privacy statutes). TODO(counsel).
class CreateDeviceLocationAttestations < ActiveRecord::Migration[7.0]
  def change
    create_table :device_location_attestations do |t|
      t.bigint  :user_id, null: false

      # verified / failed / pending — the server-side token-verification outcome. String, fail-closed:
      # only the exact "verified" string is a pass; a failed/expired/spoofed/malformed token is "failed".
      t.string  :attestation_status, null: false
      # Structured reason when NOT verified (invalid_signature / expired / spoofed / malformed /
      # provider_error) — evidence + debugging. Never drives an allow.
      t.string  :failure_reason

      # The device-location vendor that issued the token (GeoComply the reference — TODO(vendor)).
      t.string  :device_provider

      # The vendor's transaction/token id for the attestation, for the evidence trail + vendor-side
      # correlation. NOT the raw token (which is single-use and sensitive).
      t.string  :attestation_ref
      # Coarse, non-precise location the vendor asserted (e.g. ISO country) — defense-in-depth evidence.
      # Precise coordinates are deliberately NOT stored here (TODO(counsel): location-privacy).
      t.string  :asserted_country

      # The policy/ruleset version this attestation was verified under (forces re-attestation on bump).
      t.string  :attestation_policy_version, null: false

      t.string  :ip_address
      t.string  :viewer_country
      t.string  :user_agent, limit: 1024

      t.datetime :created_at, precision: 6, null: false
      # No updated_at: append-only / immutable by intent.
    end

    add_index :device_location_attestations, :user_id
    add_index :device_location_attestations,
              [:user_id, :attestation_policy_version, :attestation_status],
              name: "idx_device_attest_user_version_status"
  end
end
