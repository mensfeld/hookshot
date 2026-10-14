# frozen_string_literal: true

# Handles dispatching webhooks to configured targets.
# Routes a webhook to the targets of its endpoint, creating delivery records and enqueuing jobs for those that
# pass their filters.
class WebhookDispatcher
  # Initializes a new dispatcher for a webhook.
  # @param webhook [Webhook] the webhook to dispatch
  def initialize(webhook)
    @webhook = webhook
  end

  # Dispatches the webhook to the active targets of the endpoint that received it.
  # Creates a delivery record for each target and enqueues dispatch jobs for those passing their filters.
  # @return [void]
  def dispatch
    return unless @webhook.endpoint

    @webhook.endpoint.targets.active.find_each do |target|
      dispatch_to_target(target)
    end
  end

  # Dispatches the webhook to a specific target.
  # @param target [Target] the target to dispatch to
  # @return [Delivery] the created delivery record
  def dispatch_to_target(target)
    delivery = @webhook.deliveries.create!(target: target, status: :pending)

    if FilterEvaluator.new(@webhook, target).passes?
      DispatchJob.perform_later(delivery.id)
    else
      delivery.update!(status: :filtered)
    end

    delivery
  end
end
