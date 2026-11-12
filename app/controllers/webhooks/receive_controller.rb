# frozen_string_literal: true

# Namespace for webhook reception controllers.
module Webhooks
  # Handles incoming webhook requests.
  # Stores the webhook with the endpoint it was sent to and enqueues a job that routes it to that endpoint's targets,
  # so the sender gets its answer after storing two rows, whatever the number of targets.
  class ReceiveController < ApplicationController
    skip_before_action :verify_authenticity_token

    # Maximum allowed payload size in bytes (default: 1MB).
    MAX_PAYLOAD_SIZE = Hookshot::Settings.max_payload_size

    # Receives and processes an incoming webhook.
    # @return [void] responds with 200 OK on success, 404 for an unknown or inactive endpoint, 401 for a missing or
    #   invalid signature on an endpoint that verifies signatures
    def create
      if request.raw_post.bytesize > MAX_PAYLOAD_SIZE
        render json: { error: "Payload too large" }, status: :payload_too_large
        return
      end

      endpoint = find_endpoint
      unless endpoint
        render json: { error: "Unknown endpoint" }, status: :not_found
        return
      end

      if endpoint.verifies_signatures? && !endpoint.signature_verified?(request)
        endpoint.record_verification_failure!
        render json: { error: "Invalid signature" }, status: :unauthorized
        return
      end

      webhook = Webhook.create!(
        endpoint: endpoint,
        headers: extract_headers,
        payload: request.raw_post.b,
        content_type: request.content_type || "application/octet-stream",
        source_ip: request.remote_ip,
        received_at: Time.current
      )

      RouteWebhookJob.perform_later(webhook.id)

      head :ok
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    private

    # Rails parses the body into params before the action runs (parameter wrapping and request logging) and answers
    # 400 or 500 when it cannot: a form or multipart body that does not parse, or a form, multipart or JSON body that
    # is not valid UTF-8. A malformed JSON body is skipped by Rails before the action.
    # The action reads only the raw body and the path, so the params are the path parameters, whatever the body is.
    # @return [void]
    def process_action(*)
      request.request_parameters = {}
      request.set_header("action_dispatch.request.parameters", request.path_parameters.with_indifferent_access)
      super
    end

    # Finds the active endpoint addressed by the request: the slug from the URL path, or the default endpoint for
    # the plain /webhooks/receive URL. Reads only the path parameters, so a body or query endpoint_slug cannot pick
    # the endpoint and a body parse error does not reach this code.
    # @return [Endpoint, nil] the endpoint, or nil when it does not exist or is inactive
    def find_endpoint
      slug = request.path_parameters[:endpoint_slug]
      endpoint = slug ? Endpoint.find_by(slug: slug) : Endpoint.default
      endpoint if endpoint&.active?
    end

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
