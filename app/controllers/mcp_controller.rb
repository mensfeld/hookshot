# frozen_string_literal: true

# Model Context Protocol endpoint (Streamable HTTP transport, stateless, without SSE streams).
# Lets MCP clients run admin actions as tools, behind the admin HTTP Basic Auth.
class McpController < ApplicationController
  include Authenticatable

  skip_before_action :verify_authenticity_token
  before_action :verify_origin
  before_action :verify_protocol_version

  # Handles one JSON-RPC message posted by the client.
  # @return [void] renders the JSON-RPC response, or 202 Accepted for notifications and client responses
  def create
    message = JSON.parse(request.raw_post)
    response = Mcp::Server.new.handle(message)

    if response
      render json: response
    else
      head :accepted
    end
  rescue JSON::ParserError
    render json: Mcp::Server.error_response(nil, Mcp::Server::PARSE_ERROR, "Parse error"), status: :bad_request
  end

  # The server opens no server-to-client stream.
  # @return [void] responds with 405 Method Not Allowed
  def stream
    head :method_not_allowed
  end

  private

  # Rejects cross-origin browser requests. DNS rebinding is not covered here (the attacker's page then shares the
  # origin): Basic Auth and +config.hosts+ protect against it.
  # @return [void] renders 403 when the Origin header names another origin
  def verify_origin
    return if request.origin.blank? || request.origin == request.base_url

    head :forbidden
  end

  # Rejects a request naming a protocol version this server does not speak. Clients send the header after the
  # initialize handshake; a request without it is accepted.
  # @return [void] renders 400 for an unsupported MCP-Protocol-Version header
  def verify_protocol_version
    version = request.headers["MCP-Protocol-Version"]
    return if version.blank? || Mcp::Server::PROTOCOL_VERSIONS.include?(version)

    render json: Mcp::Server.error_response(nil, Mcp::Server::INVALID_REQUEST, "Unsupported protocol version: #{version}"),
      status: :bad_request
  end
end
