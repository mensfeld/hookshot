# frozen_string_literal: true

FactoryBot.define do
  factory :endpoint do
    sequence(:name) { |n| "Endpoint #{n}" }
    sequence(:slug) { |n| "endpoint-#{n}" }
    active { true }

    trait :inactive do
      active { false }
    end
  end
end
