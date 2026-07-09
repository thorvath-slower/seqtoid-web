FactoryBot.define do
  # CZID-597 -- Descartes restricted-party screening evidence row. Default is a CLEAN (nomatch) screen;
  # traits cover each hit level the fail-closed path must deny.
  factory :screening_result do
    sequence(:subject_ref) { |n| "user:#{n}" }
    subject_type { "User" }
    sequence(:soptionalid) { |n| n.to_s }
    transstatus { ScreeningResult::TRANSSTATUS_PASSED }
    alert_level { ScreeningResult::ALERT_NOMATCH }
    risk_country { 0 }
    list { "Export" }
    provider { "descartes" }
    screened_at { Time.current }
    raw_response_ref { "log:screen-ref" }

    trait :wl do
      alert_level { ScreeningResult::ALERT_WL }
    end

    trait :al do
      alert_level { ScreeningResult::ALERT_AL }
    end

    # Hit traits: transstatus is "On Hold-RPS" (the primary hold signal); alert_level is the severity.
    trait :yellow do
      transstatus { ScreeningResult::TRANSSTATUS_ON_HOLD }
      alert_level { ScreeningResult::ALERT_YELLOW }
      sdistributedid { "295395313516552" }
    end

    trait :red do
      transstatus { ScreeningResult::TRANSSTATUS_ON_HOLD }
      alert_level { ScreeningResult::ALERT_RED }
      sdistributedid { "295395313516553" }
    end

    trait :double_red do
      transstatus { ScreeningResult::TRANSSTATUS_ON_HOLD }
      alert_level { ScreeningResult::ALERT_DOUBLE_RED }
      sdistributedid { "295395313516554" }
    end

    trait :triple_red do
      transstatus { ScreeningResult::TRANSSTATUS_ON_HOLD }
      alert_level { ScreeningResult::ALERT_TRIPLE_RED }
      sdistributedid { "295395313516555" }
    end
  end
end
