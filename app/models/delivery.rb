# frozen_string_literal: true

# Represents a delivery attempt of a webhook to a specific target.
# Tracks the status, response, and retry attempts for each delivery.
class Delivery < ApplicationRecord
  belongs_to :webhook
  belongs_to :target

  enum :status, { pending: 0, success: 1, failed: 2, filtered: 3 }

  scope :recent_24h, -> { where("created_at >= ?", 24.hours.ago) }

  # Increments the delivery attempt counter.
  # @return [Boolean] true if the record was saved successfully
  def increment_attempts!
    increment!(:attempts)
  end

  # Checks if the delivery can be retried.
  # @return [Boolean] true if delivery failed and has fewer than 5 attempts
  def retryable?
    failed? && attempts < 5
  end
end
