# frozen_string_literal: true

require "openssl"

# Verifies the HMAC signature of an inbound webhook against the settings of the endpoint that received it.
# The signature is computed over the raw request body bytes, so a body is checked exactly as the sender signed it.
class SignatureVerifier
  # Supported HMAC digest algorithms.
  ALGORITHMS = %w[sha1 sha256 sha512].freeze

  # Supported encodings of the signature value.
  ENCODINGS = %w[hex base64].freeze

  # Supported signature header formats: a single value, or a comma-separated key=value list (Stripe).
  FORMATS = %w[plain key_value].freeze

  # Placeholders allowed in the signed-content template.
  PLACEHOLDER = /\{(?:body|timestamp|header:[^{}]+)\}/

  # Settings each preset assigns to an endpoint; "generic" keeps the settings entered by hand.
  PRESETS = {
    "github" => {
      signature_header: "X-Hub-Signature-256", signature_algorithm: "sha256", signature_encoding: "hex",
      signature_prefix: "sha256=", signature_format: "plain", signed_payload_template: "{body}"
    },
    "stripe" => {
      signature_header: "Stripe-Signature", signature_algorithm: "sha256", signature_encoding: "hex",
      signature_format: "key_value", signature_key: "v1", timestamp_key: "t",
      signed_payload_template: "{timestamp}.{body}", timestamp_tolerance: 300
    },
    "slack" => {
      signature_header: "X-Slack-Signature", signature_algorithm: "sha256", signature_encoding: "hex",
      signature_prefix: "v0=", signature_format: "plain", timestamp_header: "X-Slack-Request-Timestamp",
      signed_payload_template: "v0:{timestamp}:{body}", timestamp_tolerance: 300
    },
    "shopify" => {
      signature_header: "X-Shopify-Hmac-Sha256", signature_algorithm: "sha256", signature_encoding: "base64",
      signature_format: "plain", signed_payload_template: "{body}"
    },
    "generic" => {}
  }.freeze

  # Settings a named preset clears unless it sets them.
  PRESET_RESETS = {
    signature_prefix: nil, signature_key: nil, timestamp_key: nil, timestamp_header: nil, timestamp_tolerance: nil
  }.freeze

  # @param endpoint [Endpoint] the endpoint whose verification settings apply
  def initialize(endpoint)
    @endpoint = endpoint
  end

  # Checks the request's signature with each of the endpoint's secrets.
  # @param request [ActionDispatch::Request] the inbound webhook request
  # @return [Boolean] true when a signature in the request matches one computed with any secret
  def verified?(request)
    header = request.headers[@endpoint.signature_header]
    return false if header.blank?

    signatures, timestamp = parse_signature_header(header)
    timestamp = request.headers[@endpoint.timestamp_header] if @endpoint.timestamp_header.present?
    return false if signatures.empty? || !timestamp_valid?(timestamp)

    payload = signed_payload(request, timestamp)
    return false unless payload

    expected = @endpoint.signing_secrets_list.map { |secret| encode(OpenSSL::HMAC.digest(@endpoint.signature_algorithm, secret, payload)) }
    expected.product(signatures).any? { |computed, given| ActiveSupport::SecurityUtils.secure_compare(computed, given) }
  end

  private

  # Splits the signature header into the signatures it carries and, for a key=value list, its timestamp.
  # @param header [String] the signature header value
  # @return [Array(Array<String>, String)] signatures without the prefix, and the timestamp (nil when absent)
  def parse_signature_header(header)
    return [ [ normalize(header) ], nil ] if @endpoint.signature_format == "plain"

    pairs = header.split(",").map { |pair| pair.split("=", 2).map(&:strip) }
    signatures = pairs.filter_map { |key, value| normalize(value) if key == @endpoint.signature_key && value.present? }
    timestamp = pairs.find { |key, _| key == @endpoint.timestamp_key }&.last if @endpoint.timestamp_key.present?

    [ signatures, timestamp ]
  end

  # Strips the prefix and, for hex, the letter case from a signature, so it compares with the computed one.
  # @param signature [String] a signature as sent
  # @return [String] the signature in the encoding the verifier computes
  def normalize(signature)
    signature = signature.strip
    prefix = @endpoint.signature_prefix
    signature = signature.delete_prefix(prefix) if prefix.present?
    @endpoint.signature_encoding == "hex" ? signature.downcase : signature
  end

  # Checks the timestamp when the template signs one or a tolerance is set.
  # @param timestamp [String, nil] the timestamp as sent, in Unix seconds
  # @return [Boolean] true when no timestamp is needed, or it is present and within the tolerance
  def timestamp_valid?(timestamp)
    tolerance = @endpoint.timestamp_tolerance
    return true unless tolerance || @endpoint.signed_payload_template.include?("{timestamp}")
    return false unless timestamp.to_s.match?(/\A\d+\z/)

    tolerance.nil? || (Time.current.to_i - timestamp.to_i).abs <= tolerance
  end

  # Builds the signed content from the template, as bytes.
  # @param request [ActionDispatch::Request] the inbound webhook request
  # @param timestamp [String, nil] the request timestamp
  # @return [String, nil] the content to sign, or nil when a header the template names is missing
  def signed_payload(request, timestamp)
    @endpoint.signed_payload_template.split(/(#{PLACEHOLDER})/o).map do |part|
      value =
        case part
        when "{body}" then request.raw_post
        when "{timestamp}" then timestamp
        when /\A\{header:(.+)\}\z/ then request.headers[Regexp.last_match(1)].presence
        else part
        end
      return nil if value.nil?

      value.b
    end.join.b
  end

  # Encodes a raw digest the way the endpoint's senders encode their signatures.
  # @param digest [String] the raw HMAC digest
  # @return [String] the digest as lowercase hex or strict base64
  def encode(digest)
    @endpoint.signature_encoding == "hex" ? digest.unpack1("H*") : [ digest ].pack("m0")
  end
end
