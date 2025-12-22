# frozen_string_literal: true

FactoryBot.define do
  factory :filter do
    target
    filter_type { :header }
    field { "X-Api-Key" }
    operator { :exists }
    value { nil }

    trait :header_exists do
      filter_type { :header }
      field { "X-Api-Key" }
      operator { :exists }
    end

    trait :header_equals do
      filter_type { :header }
      field { "X-Api-Key" }
      operator { :equals }
      value { "secret123" }
    end

    trait :header_matches do
      filter_type { :header }
      field { "Authorization" }
      operator { :matches }
      value { "Bearer *" }
    end

    trait :payload_exists do
      filter_type { :payload }
      field { "$.event" }
      operator { :exists }
    end

    trait :payload_equals do
      filter_type { :payload }
      field { "$.event" }
      operator { :equals }
      value { "order.created" }
    end

    trait :payload_matches do
      filter_type { :payload }
      field { "$.data.email" }
      operator { :matches }
      value { "*@example.com" }
    end
  end
end
