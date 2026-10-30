# frozen_string_literal: true

module Mcp
  # Admin actions exposed as MCP tools. Each entry of DEFINITIONS is backed by the private method of the same name,
  # which receives the call's arguments and returns the data sent back to the client.
  class Tools
    # Raised by a tool when its arguments are invalid; reported to the client as a tool error.
    class ArgumentsError < StandardError; end

    # Default number of records a listing tool returns.
    DEFAULT_LIMIT = 20

    # Maximum number of records a listing tool returns.
    MAX_LIMIT = 100

    # Maximum number of payload bytes get_webhook returns.
    PAYLOAD_PREVIEW_BYTES = 10_000

    # Input schema of the +limit+ argument shared by the listing tools.
    LIMIT_PROPERTY = {
      type: "integer", minimum: 1, maximum: MAX_LIMIT, description: "Maximum number of records (default #{DEFAULT_LIMIT})"
    }.freeze

    # Tool names mapped to their description and input properties. Properties listed in +required+ must be present.
    DEFINITIONS = {
      "list_endpoints" => {
        description: "List endpoints (named receive URLs) with their attached target ids.",
        properties: {}
      },
      "list_targets" => {
        description: "List targets (destination URLs) with their endpoints and 24h success rate.",
        properties: {}
      },
      "set_target_active" => {
        description: "Activate or deactivate a target. Inactive targets receive no new deliveries.",
        properties: { id: { type: "integer" }, active: { type: "boolean" } },
        required: %w[id active]
      },
      "list_webhooks" => {
        description: "List received webhooks, newest first.",
        properties: {
          endpoint_id: { type: "integer", description: "Only webhooks received by this endpoint" },
          query: { type: "string", description: "Text to search for in headers and payload" },
          limit: LIMIT_PROPERTY
        }
      },
      "get_webhook" => {
        description: "Show a webhook with its headers, payload (first #{PAYLOAD_PREVIEW_BYTES} bytes) and deliveries.",
        properties: { id: { type: "integer" } },
        required: %w[id]
      },
      "replay_webhook" => {
        description: "Dispatch a webhook again to the active targets of the endpoint that received it.",
        properties: { id: { type: "integer" } },
        required: %w[id]
      },
      "list_dispatches" => {
        description: "List deliveries (dispatches of a webhook to a target), newest first.",
        properties: {
          status: { type: "string", enum: Delivery.statuses.keys },
          target_id: { type: "integer" },
          limit: LIMIT_PROPERTY
        }
      },
      "retry_dispatch" => {
        description: "Queue a failed delivery for retry. Only failed deliveries with attempts left can be retried.",
        properties: { id: { type: "integer" } },
        required: %w[id]
      }
    }.freeze

    # Lists the tools in the shape of an MCP tools/list result.
    # @return [Array<Hash>] tool name, description and input schema of every tool
    def definitions
      DEFINITIONS.map do |name, definition|
        {
          name: name,
          description: definition[:description],
          inputSchema: { type: "object", properties: definition[:properties], required: definition.fetch(:required, []) }
        }
      end
    end

    # Tells whether a tool exists.
    # @param name [String] tool name
    # @return [Boolean] true when the tool is defined
    def known?(name)
      DEFINITIONS.key?(name)
    end

    # Runs a tool. Failures the client can act on (bad arguments, a missing record) are returned as a tool error.
    # @param name [String] name of a defined tool
    # @param arguments [Hash] arguments sent by the client, keyed by name
    # @return [Hash] MCP tools/call result with the outcome as JSON text
    def call(name, arguments)
      arguments = arguments.is_a?(Hash) ? arguments : {}
      missing = DEFINITIONS.fetch(name).fetch(:required, []) - arguments.keys
      raise ArgumentsError, "Missing arguments: #{missing.join(', ')}" if missing.any?

      tool_result(send(name, arguments), error: false)
    rescue ArgumentsError, ActiveRecord::RecordNotFound, ActiveRecord::RecordInvalid => e
      tool_result({ error: e.message }, error: true)
    end

    private

    # Wraps tool output in an MCP tools/call result.
    # @param data [Hash, Array] the tool output
    # @param error [Boolean] whether the tool failed
    # @return [Hash] the tools/call result
    def tool_result(data, error:)
      { content: [ { type: "text", text: JSON.pretty_generate(data) } ], isError: error }
    end

    # @param _arguments [Hash] unused
    # @return [Array<Hash>] every endpoint
    def list_endpoints(_arguments)
      Endpoint.includes(:endpoint_targets).order(:name).map do |endpoint|
        endpoint.slice(:id, :name, :slug, :active).merge(target_ids: endpoint.endpoint_targets.map(&:target_id))
      end
    end

    # @param _arguments [Hash] unused
    # @return [Array<Hash>] every target, without its custom headers
    def list_targets(_arguments)
      targets = Target.includes(:endpoints).order(:name).to_a
      success_rates = Target.success_rates_24h(targets.map(&:id))

      targets.map do |target|
        target.slice(:id, :name, :url, :active, :timeout).merge(
          endpoint_slugs: target.endpoints.map(&:slug),
          success_rate_24h: success_rates.fetch(target.id)
        )
      end
    end

    # @param arguments [Hash] +id+ and +active+
    # @return [Hash] the updated target
    def set_target_active(arguments)
      raise ArgumentsError, "active must be true or false" unless [ true, false ].include?(arguments["active"])

      target = Target.find(integer(arguments, "id"))
      target.update!(active: arguments["active"])
      target.slice(:id, :name, :active)
    end

    # @param arguments [Hash] optional +endpoint_id+, +query+ and +limit+
    # @return [Array<Hash>] matching webhooks
    def list_webhooks(arguments)
      webhooks = Webhook.includes(:endpoint)
        .for_endpoint(arguments["endpoint_id"])
        .search_text(arguments["query"])
        .order(received_at: :desc)
        .limit(limit(arguments))
        .to_a
      stats = Webhook.dispatch_stats_for(webhooks.map(&:id))

      webhooks.map { |webhook| webhook_summary(webhook, stats.fetch(webhook.id)) }
    end

    # @param arguments [Hash] +id+
    # @return [Hash] the webhook with its headers, payload preview and deliveries
    def get_webhook(arguments)
      webhook = Webhook.find(integer(arguments, "id"))
      payload = webhook.display_payload

      webhook_summary(webhook, webhook.dispatch_stats).merge(
        headers: webhook.headers,
        payload: payload.byteslice(0, PAYLOAD_PREVIEW_BYTES).scrub(""),
        payload_truncated: payload.bytesize > PAYLOAD_PREVIEW_BYTES,
        deliveries: webhook.deliveries.includes(:target).order(created_at: :desc).map { |delivery| delivery_summary(delivery) }
      )
    end

    # @param arguments [Hash] +id+
    # @return [Hash] the outcome of the replay
    def replay_webhook(arguments)
      webhook = Webhook.find(integer(arguments, "id"))
      raise ArgumentsError, "Webhook #{webhook.id} cannot be replayed: its endpoint was deleted" unless webhook.endpoint

      WebhookDispatcher.new(webhook).dispatch
      { id: webhook.id, replayed_to_endpoint: webhook.endpoint.slug }
    end

    # @param arguments [Hash] optional +status+, +target_id+ and +limit+
    # @return [Array<Hash>] matching deliveries
    def list_dispatches(arguments)
      scope = Delivery.includes(:target).order(created_at: :desc).limit(limit(arguments))
      if arguments["status"].present?
        raise ArgumentsError, "Unknown status: #{arguments['status']}" unless Delivery.statuses.key?(arguments["status"])

        scope = scope.where(status: arguments["status"])
      end
      scope = scope.where(target_id: arguments["target_id"]) if arguments["target_id"].present?
      scope.map { |delivery| delivery_summary(delivery) }
    end

    # @param arguments [Hash] +id+
    # @return [Hash] the delivery and whether it was queued
    def retry_dispatch(arguments)
      delivery = Delivery.find(integer(arguments, "id"))
      raise ArgumentsError, "Delivery #{delivery.id} cannot be retried (status #{delivery.status}, #{delivery.attempts} attempts)" unless delivery.retry!

      { id: delivery.id, queued: true }
    end

    # @param webhook [Webhook] the webhook to summarize
    # @param dispatch_stats [Hash] the webhook's delivery counts, from Webhook.dispatch_stats_for
    # @return [Hash] the webhook's listing fields
    def webhook_summary(webhook, dispatch_stats)
      webhook.slice(:id, :content_type, :source_ip, :received_at, :payload_size).merge(
        endpoint_slug: webhook.endpoint&.slug,
        dispatch_stats: dispatch_stats
      )
    end

    # @param delivery [Delivery] the delivery to summarize
    # @return [Hash] the delivery's listing fields
    def delivery_summary(delivery)
      delivery.slice(:id, :webhook_id, :target_id, :status, :status_code, :attempts, :error_message, :next_retry_at, :created_at)
        .merge(target_name: delivery.target&.name)
    end

    # Reads a required integer argument.
    # @param arguments [Hash] arguments sent by the client, keyed by name
    # @param key [String] argument name
    # @return [Integer] the argument's value
    def integer(arguments, key)
      Integer(arguments[key])
    rescue ArgumentError, TypeError
      raise ArgumentsError, "#{key} must be an integer"
    end

    # Reads the +limit+ argument, clamped to 1..MAX_LIMIT.
    # @param arguments [Hash] arguments sent by the client, keyed by name
    # @return [Integer] the number of records to return
    def limit(arguments)
      return DEFAULT_LIMIT if arguments["limit"].blank?

      integer(arguments, "limit").clamp(1, MAX_LIMIT)
    end
  end
end
