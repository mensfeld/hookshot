# frozen_string_literal: true

require_relative "../../../lib/hookshot/version"

# Namespace for the Model Context Protocol (MCP) server.
module Mcp
  # Answers MCP JSON-RPC 2.0 messages: the initialize handshake, ping, tools/list and tools/call.
  # Transport-agnostic: takes one parsed message and returns the response to send back.
  class Server
    # Protocol versions this server speaks, newest first.
    PROTOCOL_VERSIONS = %w[2025-11-25 2025-06-18 2025-03-26 2024-11-05].freeze

    # JSON-RPC error code for a body that is not valid JSON.
    PARSE_ERROR = -32_700

    # JSON-RPC error code for a message that is not a valid request.
    INVALID_REQUEST = -32_600

    # JSON-RPC error code for an unknown method.
    METHOD_NOT_FOUND = -32_601

    # JSON-RPC error code for invalid method parameters.
    INVALID_PARAMS = -32_602

    # Builds a JSON-RPC error response.
    # @param id [String, Integer, nil] id of the request that failed
    # @param code [Integer] JSON-RPC error code
    # @param message [String] human-readable error
    # @return [Hash] the error response
    def self.error_response(id, code, message)
      { jsonrpc: "2.0", id: id, error: { code: code, message: message } }
    end

    # @param tools [Mcp::Tools] the tools this server exposes
    def initialize(tools: Tools.new)
      @tools = tools
    end

    # Handles one JSON-RPC message.
    # @param message [Object] the parsed message
    # @return [Hash, nil] the response, or nil for notifications and client responses, which get none
    def handle(message)
      unless message.is_a?(Hash) && message["jsonrpc"] == "2.0" && (message["method"].nil? || message["method"].is_a?(String))
        return self.class.error_response(nil, INVALID_REQUEST, "Invalid Request")
      end
      return unless message.key?("id") && message["method"]

      id = message["id"]
      params = message["params"].is_a?(Hash) ? message["params"] : {}

      result =
        case message["method"]
        when "initialize" then initialize_result(params)
        when "ping" then {}
        when "tools/list" then { tools: @tools.definitions }
        when "tools/call"
          return self.class.error_response(id, INVALID_PARAMS, "Unknown tool: #{params['name']}") unless @tools.known?(params["name"])

          @tools.call(params["name"], params["arguments"] || {})
        else
          return self.class.error_response(id, METHOD_NOT_FOUND, "Method not found: #{message['method']}")
        end

      { jsonrpc: "2.0", id: id, result: result }
    end

    private

    # Answers the initialize handshake, agreeing on the client's protocol version when supported.
    # @param params [Hash] initialize parameters sent by the client
    # @return [Hash] the initialize result
    def initialize_result(params)
      requested = params["protocolVersion"]

      {
        protocolVersion: PROTOCOL_VERSIONS.include?(requested) ? requested : PROTOCOL_VERSIONS.first,
        capabilities: { tools: { listChanged: false } },
        serverInfo: { name: "hookshot", version: Hookshot::VERSION }
      }
    end
  end
end
