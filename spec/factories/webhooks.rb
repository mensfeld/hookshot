# frozen_string_literal: true

FactoryBot.define do
  factory :webhook do
    headers { { "HTTP_CONTENT_TYPE" => "application/json", "HTTP_X_API_KEY" => "test-key" } }
    payload { { event: "test.event", data: { id: 1 } }.to_json }
    content_type { "application/json" }
    source_ip { "127.0.0.1" }
    received_at { Time.current }

    trait :without_payload do
      payload { nil }
    end

    trait :form_data do
      headers { { "HTTP_CONTENT_TYPE" => "application/x-www-form-urlencoded" } }
      payload { "event=test&data[id]=1" }
      content_type { "application/x-www-form-urlencoded" }
    end
  end
end
