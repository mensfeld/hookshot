# frozen_string_literal: true

FactoryBot.define do
  factory :target do
    sequence(:name) { |n| "Target #{n}" }
    url { "https://api.example.com/webhook" }
    active { true }
    custom_headers { {} }
    timeout { 30 }

    trait :inactive do
      active { false }
    end

    trait :with_auth_header do
      custom_headers { { "Authorization" => "Bearer secret-token" } }
    end

    trait :with_filters do
      after(:create) do |target|
        create(:filter, :header_exists, target: target)
      end
    end

    trait :with_filter do
      after(:create) do |target|
        create(:filter, target: target)
      end
    end
  end
end
