# frozen_string_literal: true

FactoryBot.define do
  factory :delivery do
    webhook
    target
    status { :pending }
    status_code { nil }
    response_body { nil }
    error_message { nil }
    attempts { 0 }
    dispatched_at { nil }

    trait :success do
      status { :success }
      status_code { 200 }
      response_body { '{"status": "ok"}' }
      attempts { 1 }
      dispatched_at { Time.current }
    end

    trait :failed do
      status { :failed }
      status_code { 500 }
      error_message { "Internal Server Error" }
      attempts { 5 }
      dispatched_at { Time.current }
    end

    trait :filtered do
      status { :filtered }
      attempts { 0 }
    end

    trait :retryable do
      status { :failed }
      attempts { 2 }
    end
  end
end
