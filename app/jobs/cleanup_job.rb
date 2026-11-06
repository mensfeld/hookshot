# frozen_string_literal: true

# Cleans up old webhooks and their associated deliveries.
# Runs on a schedule to remove data older than the configured retention period.
# Deletes in small batches, each in its own short transaction, so incoming webhooks never wait long for the
# SQLite write lock.
class CleanupJob < ApplicationJob
  queue_as :low

  # Webhooks deleted per batch.
  BATCH_SIZE = 500

  # Seconds to pause between batches so other writers can take the lock.
  PAUSE = 0.1

  # Deletes webhooks older than the retention period, together with their deliveries.
  # The retention period is configured via the RETENTION_DAYS environment variable.
  # @return [void]
  def perform
    retention_days = Hookshot::Settings.retention_days
    deleted_count = 0

    Webhook.older_than(retention_days).in_batches(of: BATCH_SIZE) do |batch|
      ids = batch.ids

      Webhook.transaction do
        Delivery.where(webhook_id: ids).delete_all
        Webhook.where(id: ids).delete_all
      end

      deleted_count += ids.size
      sleep(PAUSE)
    end

    Rails.logger.info "[CleanupJob] Deleted #{deleted_count} webhooks older than #{retention_days} days"
  end
end
