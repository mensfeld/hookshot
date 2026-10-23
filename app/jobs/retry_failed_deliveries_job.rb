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

    deliveries.find_each do |delivery|
      delivery.reset_for_retry!
      DispatchJob.perform_later(delivery.id)
      Rails.logger.info "[RetryFailedDeliveriesJob] Scheduled retry for delivery #{delivery.id} (attempt #{delivery.attempts + 1}/#{Delivery::MAX_TOTAL_ATTEMPTS})"
      processed_count += 1
    end

    if processed_count > 0
      Rails.logger.info "[RetryFailedDeliveriesJob] Processed #{processed_count} deliveries"
    end
  end
end
