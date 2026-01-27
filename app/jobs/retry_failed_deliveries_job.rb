# frozen_string_literal: true

# Recurring job that retries failed deliveries in the recurring job phase.
# Runs every 5 minutes to check for deliveries ready for retry.
class RetryFailedDeliveriesJob < ApplicationJob
  queue_as :low

  # Processes failed deliveries that are ready for retry.
  # @return [void]
  def perform
    deliveries = Delivery.ready_for_retry.limit(100)
    processed_count = 0
    exhausted_count = 0

    deliveries.find_each do |delivery|
      if delivery.attempts >= Delivery::MAX_TOTAL_ATTEMPTS
        Rails.logger.warn "[RetryFailedDeliveriesJob] Delivery #{delivery.id} exhausted all retry attempts"
        exhausted_count += 1
        next
      end

      delivery.reset_for_retry!
      DispatchJob.perform_later(delivery.id)
      Rails.logger.info "[RetryFailedDeliveriesJob] Scheduled retry for delivery #{delivery.id} (attempt #{delivery.attempts + 1}/#{Delivery::MAX_TOTAL_ATTEMPTS})"
      processed_count += 1
    end

    if processed_count > 0 || exhausted_count > 0
      Rails.logger.info "[RetryFailedDeliveriesJob] Processed #{processed_count} deliveries, #{exhausted_count} failed/exhausted"
    end
  end
end
