# frozen_string_literal: true

# Cleans up old webhooks and their associated deliveries.
# Runs on a schedule to remove data older than the configured retention period.
class CleanupJob < ApplicationJob
  queue_as :low

  # Deletes webhooks older than the retention period.
  # The retention period is configured via the RETENTION_DAYS environment variable.
  # @return [void]
  def perform
    retention_days = ENV.fetch("RETENTION_DAYS", 30).to_i
    deleted_count = Webhook.older_than(retention_days).destroy_all.count

    Rails.logger.info "[CleanupJob] Deleted #{deleted_count} webhooks older than #{retention_days} days"
  end
end
