FactoryBot.define do
  # CZID-597 -- a restricted-party hold. Default is an ACTIVE hold (released_at nil) triggered by a hit.
  factory :hold do
    sequence(:subject_ref) { |n| "user:#{n}" }
    subject_type { "User" }
    reason { Hold::REASON_SCREENING_HIT }
    association :screening_result, :red
    released_at { nil }

    trait :error do
      reason { Hold::REASON_SCREENING_ERROR }
      screening_result { nil }
    end

    trait :released do
      released_at { Time.current }
    end
  end
end
