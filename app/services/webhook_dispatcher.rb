# frozen_string_literal: true

# Handles dispatching webhooks to configured targets.
# Creates delivery records and enqueues jobs for targets that pass filters.
class WebhookDispatcher
  # Initializes a new dispatcher for a webhook.
  # @param webhook [Webhook] the webhook to dispatch
  def initialize(webhook)
    @webhook = webhook
  end

  # Dispatches the webhook to all active targets.
  # Creates a delivery record for each target and enqueues dispatch jobs.
  # @return [void]
  def dispatch_to_all_targets
    Target.active.find_each do |target|
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
