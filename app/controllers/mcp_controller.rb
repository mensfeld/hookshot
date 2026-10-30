# frozen_string_literal: true

# Model Context Protocol endpoint (Streamable HTTP transport, stateless, without SSE streams).
# Lets MCP clients run admin actions as tools, behind the admin HTTP Basic Auth.
class McpController < ApplicationController
  include Authenticatable

  skip_before_action :verify_authenticity_token
  before_action :verify_origin

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

  # Rejects browser requests from other origins (DNS rebinding protection required by the MCP transport).
  # @return [void] renders 403 when the Origin header names another host
  def verify_origin
    return if request.origin.blank? || request.origin == request.base_url

    head :forbidden
  end
end
