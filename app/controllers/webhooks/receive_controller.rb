# frozen_string_literal: true

# Namespace for webhook reception controllers.
module Webhooks
  # Handles incoming webhook requests.
  # Stores the webhook with the endpoint it was sent to and dispatches it to that endpoint's targets.
  class ReceiveController < ApplicationController
    skip_before_action :verify_authenticity_token

    # Maximum allowed payload size in bytes (default: 1MB).
    MAX_PAYLOAD_SIZE = ENV.fetch("MAX_PAYLOAD_SIZE", 1_048_576).to_i

    # Receives and processes an incoming webhook.
    # @return [void] responds with 200 OK on success, 404 for an unknown or inactive endpoint
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

      webhook = Webhook.create!(
        endpoint: endpoint,
        headers: extract_headers,
        payload: request.raw_post.b,
        content_type: request.content_type || "application/octet-stream",
        source_ip: request.remote_ip,
        received_at: Time.current
      )

      WebhookDispatcher.new(webhook).dispatch

      head :ok
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    private

    # Rails parses the body into params before the action runs (request logging) and answers 400 when a form or
    # multipart body cannot be parsed. The action reads only the raw body and the path, so an unparsable body falls
    # back to the path parameters and is stored like any other.
    # @return [void]
    def process_action(*)
      ignore_unparsable_parameters
      super
    end

    # Replaces the request parameters with the path parameters when the body or query string cannot be parsed.
    # A malformed JSON body is left as is: Rails already skips its ParseError before the action.
    # @return [void]
    def ignore_unparsable_parameters
      request.parameters
    rescue ActionController::BadRequest
      request.set_header("action_dispatch.request.parameters", request.path_parameters.with_indifferent_access)
    rescue ActionDispatch::Http::Parameters::ParseError
      nil
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
