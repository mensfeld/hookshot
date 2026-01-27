# frozen_string_literal: true

# Represents a delivery attempt of a webhook to a specific target.
# Tracks the status, response, and retry attempts for each delivery.
class Delivery < ApplicationRecord
  belongs_to :webhook
  belongs_to :target

  enum :status, { pending: 0, success: 1, failed: 2, filtered: 3 }
  enum :retry_stage, { activejob_phase: 0, recurring_job_phase: 1 }

  # Retry schedule: 10 attempts over ~40 hours
  # Attempts 1-5: ActiveJob phase (30s, 2m, 5m, 15m, 30m)
  # Attempts 6-10: Recurring job phase (1h, 2h, 4h, 8h, 24h)
  RETRY_SCHEDULE = [
    30.seconds,    # Attempt 1
    2.minutes,     # Attempt 2
    5.minutes,     # Attempt 3
    15.minutes,    # Attempt 4
    30.minutes,    # Attempt 5
    1.hour,        # Attempt 6
    2.hours,       # Attempt 7
    4.hours,       # Attempt 8
    8.hours,       # Attempt 9
    24.hours       # Attempt 10
  ].freeze

  # Maximum number of retry attempts before giving up
  MAX_TOTAL_ATTEMPTS = 10

  # Maximum number of retries in the ActiveJob phase before transitioning to recurring job phase
  ACTIVEJOB_MAX_ATTEMPTS = 5

  scope :recent_24h, -> { where("created_at >= ?", 24.hours.ago) }
  scope :ready_for_retry, lambda {
    where(status: :failed, retry_stage: :recurring_job_phase)
      .where("next_retry_at <= ?", Time.current)
      .where("attempts < ?", MAX_TOTAL_ATTEMPTS)
  }

  # Increments the delivery attempt counter and calculates next retry time.
  # @return [Boolean] true if the record was saved successfully
  def increment_attempts!
    self.attempts += 1
    self.last_retry_at = Time.current
    calculate_next_retry!
    save!
  end

  # Calculates and sets the next retry timestamp based on current attempts.
  # @return [Time, nil] the next retry time or nil if no more retries
  def calculate_next_retry!
    return unless attempts < MAX_TOTAL_ATTEMPTS

    delay = RETRY_SCHEDULE[attempts] || RETRY_SCHEDULE.last
    self.next_retry_at = Time.current + delay
  end

  # Checks if the delivery can be retried.
  # @return [Boolean] true if delivery failed and has fewer than MAX_TOTAL_ATTEMPTS
  def retryable?
    failed? && attempts < MAX_TOTAL_ATTEMPTS
  end

  # Checks if the delivery is ready to transition to recurring job phase.
  # @return [Boolean] true if delivery has completed ActiveJob phase
  def ready_for_recurring_phase?
    attempts >= ACTIVEJOB_MAX_ATTEMPTS && activejob_phase?
  end

  # Transitions the delivery to recurring job phase management.
  # This is called after ActiveJob exhausts its retry attempts.
  # @return [Boolean] true if transition was successful
  def transition_to_recurring_phase!
    return false unless ready_for_recurring_phase?

    self.retry_stage = :recurring_job_phase
    calculate_next_retry!
    save!
  end

  # Resets the delivery status to pending for retry.
  # @return [Boolean] true if reset was successful
  def reset_for_retry!
    update!(status: :pending)
  end
end
