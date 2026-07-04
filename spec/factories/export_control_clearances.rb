FactoryBot.define do
  # CZID-285 — Layer 3 identity/screening clearance evidence record. Default factory is a PASSED clearance
  # (verified + clear); traits cover every fail-closed branch the gate must DENY.
  factory :export_control_clearance do
    association :user
    verification_status { ExportControlClearance::VERIFICATION_VERIFIED }
    screening_result { ExportControlClearance::SCREENING_CLEAR }
    clearance_version { ExportControlClearance::CURRENT_VERSION }
    idv_provider { "reference_stub" }
    screening_provider { "reference_stub" }
    ip_address { "203.0.113.7" }
    viewer_country { "US" }
    user_agent { "RSpec" }

    trait :verification_pending do
      verification_status { ExportControlClearance::VERIFICATION_PENDING }
    end

    trait :verification_failed do
      verification_status { ExportControlClearance::VERIFICATION_FAILED }
    end

    trait :screening_hit do
      screening_result { ExportControlClearance::SCREENING_HIT }
    end

    trait :screening_pending do
      screening_result { ExportControlClearance::SCREENING_PENDING }
    end

    trait :stale_version do
      clearance_version { "v0-old" }
    end
  end
end
