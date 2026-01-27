# frozen_string_literal: true

# Dispatches a webhook delivery to its target endpoint.
# Handles retries with exponential backoff for server errors.
class DispatchJob < ApplicationJob
  # Raised when a client error (4xx) response is received.
  class ClientError < StandardError; end

  # Raised when a server error (5xx) response is received.
  class ServerError < StandardError; end

  queue_as :default

  limits_concurrency to: 10, key: -> (_job) { "dispatch" }

  retry_on StandardError, wait: :polynomially_longer, attempts: 5
  discard_on ActiveRecord::RecordNotFound
  discard_on ClientError

  # Performs the webhook delivery.
  # @param delivery_id [Integer] ID of the delivery record to process
  # @return [void]
  def perform(delivery_id)
    delivery = Delivery.find(delivery_id)
    return if delivery.success? || delivery.filtered?

    delivery.increment_attempts!
    result = execute_dispatch(delivery)
    update_delivery(delivery, result)

    # Don't retry on client errors (4xx)
    if result.status_code&.between?(400, 499)
      raise ClientError, "Client error: #{result.status_code}"
    end

    raise ServerError, result.error unless result.success?
  end

  private

  # Executes the HTTP dispatch to the target.
  # @param delivery [Delivery] contains webhook data and target configuration
  # @return [HttpClient::Result] the HTTP response result
  def execute_dispatch(delivery)
    webhook = delivery.webhook
    target = delivery.target

    client = HttpClient.new(url: target.url, timeout: target.timeout)

    headers = build_headers(webhook, target, delivery)
    client.post(body: webhook.payload, headers: headers)
  end

  # Builds the request headers for the dispatch.
  # @param webhook [Webhook] the webhook being dispatched
  # @param target [Target] the target endpoint
  # @param delivery [Delivery] the delivery record
  # @return [Hash] merged headers including custom target headers
  def build_headers(webhook, target, delivery)
    base_headers = {
      "Content-Type" => webhook.content_type,
      "X-Hookshot-Webhook-Id" => webhook.id.to_s,
      "X-Hookshot-Delivery-Id" => delivery.id.to_s,
      "User-Agent" => "Hookshot/1.0"
    }

    target.custom_headers.merge(base_headers)
  end

  # Updates the delivery record with the result.
  # @param delivery [Delivery] the delivery to update
  # @param result [HttpClient::Result] the HTTP response result
  # @return [void]
  def update_delivery(delivery, result)
    delivery.update!(
      status: result.success? ? :success : :failed,
      status_code: result.status_code,
      response_body: result.body,
      error_message: result.error,
      dispatched_at: Time.current
    )
  end
end
