# frozen_string_literal: true

FactoryBot.define do
  factory :error_record do
    sequence(:error_class) { |n| "Error#{n}" }
    sequence(:message) { |n| "Something went wrong #{n}" }
    backtrace { "app/controllers/some_controller.rb:42:in `action'\napp/services/service.rb:10:in `call'" }
    context { { source: "test" } }
    fingerprint { Digest::SHA256.hexdigest("#{error_class}:#{message}") }
    occurrences_count { 1 }
    first_occurred_at { Time.current }
    last_occurred_at { Time.current }
    resolved_at { nil }

    trait :resolved do
      resolved_at { Time.current }
    end

    trait :high_occurrences do
      occurrences_count { 15 }
    end

    trait :with_job_context do
      context do
        {
          source: "job",
          job: {
            class: "SomeJob",
            queue: "default",
            arguments: [ "arg1", "arg2" ]
          }
        }
      end
    end

    trait :with_controller_context do
      context do
        {
          source: "controller",
          controller: {
            name: "webhooks",
            action: "create",
            params: { "foo" => "bar" }
          }
        }
      end
    end
  end
end
