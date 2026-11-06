# frozen_string_literal: true

# Routes a received webhook to the targets of the endpoint that received it.
# The receive request only stores the webhook and enqueues this job, so it answers the sender after one database
# write instead of one per target. Creating the deliveries here keeps bursts of webhooks from queueing on the
# SQLite write lock long enough for senders to time out.
class RouteWebhookJob < ApplicationJob
  queue_as :default

  # Runs before the dispatch jobs waiting in the same queue, so a burst is stored and routed first and the
  # deliveries follow.
  queue_with_priority(-10)

  retry_on StandardError, wait: :polynomially_longer, attempts: 10

  # Declared after retry_on: the last declared matching handler wins
  discard_on ActiveRecord::RecordNotFound

  # Creates a delivery for each active target of the webhook's endpoint and enqueues those that pass their filters.
  # Skips targets that already have a delivery of this webhook, so a retry after a partial run does not deliver twice.
  # @param webhook_id [Integer] ID of the webhook to route
  # @return [void]
  def perform(webhook_id)
    WebhookDispatcher.new(Webhook.find(webhook_id)).dispatch(skip_routed: true)
  end
end
