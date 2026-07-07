# frozen_string_literal: true

# Namespace for webhook reception controllers.
module Webhooks
  # Handles incoming webhook requests.
  # Stores the webhook and dispatches it to configured targets.
  class ReceiveController < ApplicationController
    skip_before_action :verify_authenticity_token

    # Maximum allowed payload size in bytes (default: 1MB).
    MAX_PAYLOAD_SIZE = ENV.fetch("MAX_PAYLOAD_SIZE", 1_048_576).to_i

    # Receives and processes an incoming webhook.
    # @return [void] responds with 200 OK on success
    def create
      if request.raw_post.bytesize > MAX_PAYLOAD_SIZE
        render json: { error: "Payload too large" }, status: :payload_too_large
        return
      end

      webhook = Webhook.create!(
        headers: extract_headers,
        payload: to_utf8(request.raw_post),
        content_type: request.content_type || "application/octet-stream",
        source_ip: request.remote_ip,
        received_at: Time.current
      )

      WebhookDispatcher.new(webhook).dispatch_to_all_targets

      head :ok
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    private

    # Extracts relevant headers from the request.
    # @return [Hash] filtered headers including HTTP_* and content headers
    def extract_headers
      request.headers.to_h.each_with_object({}) do |(key, value), headers|
        next unless key.start_with?("HTTP_") || %w[CONTENT_TYPE CONTENT_LENGTH].include?(key)

        headers[key] = value.is_a?(String) ? to_utf8(value) : value
      end
    end

    # Forces a raw (often ASCII-8BIT) string to valid UTF-8, replacing any
    # invalid or incomplete byte sequences instead of raising on them.
    # @param string [String] the raw string to convert
    # @return [String] a valid UTF-8 string
    def to_utf8(string)
      string.dup.force_encoding(Encoding::UTF_8).scrub
    end
  end
end
