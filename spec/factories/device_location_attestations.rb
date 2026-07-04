FactoryBot.define do
  # CZID-286 — Layer 3 device/location attestation evidence record. Default is a VERIFIED attestation;
  # traits cover the fail-closed branches.
  factory :device_location_attestation do
    association :user
    attestation_status { DeviceLocationAttestation::STATUS_VERIFIED }
    attestation_policy_version { DeviceLocationAttestation::CURRENT_VERSION }
    device_provider { "reference_stub" }
    asserted_country { "US" }
    ip_address { "203.0.113.7" }
    viewer_country { "US" }
    user_agent { "RSpec" }

    trait :pending do
      attestation_status { DeviceLocationAttestation::STATUS_PENDING }
    end

    trait :failed do
      attestation_status { DeviceLocationAttestation::STATUS_FAILED }
      failure_reason { DeviceLocationAttestation::FAILURE_SPOOFED }
    end

    trait :stale_version do
      attestation_policy_version { "v0-old" }
    end
  end
end
