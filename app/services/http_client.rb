# frozen_string_literal: true

require "net/http"
require "uri"

# HTTP client for making POST requests to target endpoints.
# Uses Net::HTTP from Ruby stdlib for minimal external dependencies.
class HttpClient
  # Result object containing response data from an HTTP request.
  Result = Data.define(:success?, :status_code, :body, :error)

  # Maximum response body size to store (10KB).
  MAX_RESPONSE_SIZE = 10_000

  # Initializes a new HTTP client.
  # @param url [String] target URL to send requests to
  # @param timeout [Integer] request timeout in seconds (default: 30)
  def initialize(url:, timeout: 30)
    @uri = URI.parse(url)
    @timeout = timeout
  end

  # Sends a POST request with the given body and headers.
  # @param body [String] request body content
  # @param headers [Hash] request headers
  # @return [Result] result object with success status, code, body, and error
  def post(body:, headers: {})
    http = build_http
    request = build_request(body, headers)

    response = http.request(request)
    Result.new(
      success?: response.code.to_i.between?(200, 299),
      status_code: response.code.to_i,
      body: truncate_body(response.body),
      error: nil
    )
  rescue Net::OpenTimeout, Net::ReadTimeout => e
    Result.new(success?: false, status_code: nil, body: nil, error: "Timeout: #{e.message}")
  rescue SocketError, Errno::ECONNREFUSED, Errno::EHOSTUNREACH => e
    Result.new(success?: false, status_code: nil, body: nil, error: "Connection error: #{e.message}")
  rescue StandardError => e
    Result.new(success?: false, status_code: nil, body: nil, error: e.message)
  end

  private

  # Builds and configures the Net::HTTP object.
  # @return [Net::HTTP] configured HTTP client
  def build_http
    http = Net::HTTP.new(@uri.host, @uri.port)
    http.use_ssl = @uri.scheme == "https"
    http.open_timeout = @timeout
    http.read_timeout = @timeout
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER if http.use_ssl?
    http
  end

  # Builds the HTTP POST request with body and headers.
  # @param body [String] request body
  # @param headers [Hash] request headers
  # @return [Net::HTTP::Post] configured POST request
  def build_request(body, headers)
    request = Net::HTTP::Post.new(@uri.request_uri)
    headers.each { |k, v| request[k] = v.to_s }
    request.body = body
    request
  end

  # Truncates response body to maximum allowed size.
  # @param body [String, nil] response body
  # @return [String, nil] truncated body or nil
  def truncate_body(body)
    return nil if body.nil?
    body.truncate(MAX_RESPONSE_SIZE)
  end
end
