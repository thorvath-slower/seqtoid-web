FactoryBot.define do
  # CZID-330 — export-control attestation evidence record.
  factory :export_control_attestation do
    association :user
    decision { ExportControlAttestation::DECISION_ACCEPTED }
    attestation_version { ExportControlAttestation::CURRENT_VERSION }
    ip_address { "203.0.113.7" }
    viewer_country { "US" }
    user_agent { "RSpec" }
  end
end
