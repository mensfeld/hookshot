# frozen_string_literal: true

require "openssl"

module VerificationProviders
  # Base class of signature verification providers. A provider implements +verified?+ and may use the HMAC helpers.
  class Base
    # Returns the provider name shown in the admin.
    # @return [String] the provider name
    def self.label
      name.demodulize
    end

    # @param endpoint [Endpoint] the endpoint that received the request
    def initialize(endpoint)
      @endpoint = endpoint
    end

    # Checks whether a request is authentic.
    # @param request [ActionDispatch::Request] the inbound webhook request; +raw_post+ is the body as received
    # @return [Boolean] true when the request carries a valid signature
    def verified?(request)
      raise NotImplementedError, "#{self.class.name} must implement #verified?"
    end

    private

    # @return [Endpoint] the endpoint that received the request
    attr_reader :endpoint

    # Returns the endpoint's secrets; a request signed with any of them is accepted.
    # @return [Array<String>] the signing secrets
    def secrets
      endpoint.signing_secrets_list
    end

    # Computes an HMAC over the parts in order, without joining them into one string.
    # @param algorithm [String] the digest name, e.g. "sha256"
    # @param secret [String] the signing secret
    # @param parts [Array<String>] the signed content, e.g. the raw body
    # @return [String] the raw digest
    def hmac(algorithm, secret, *parts)
      digest = OpenSSL::HMAC.new(secret, algorithm)
      parts.each { |part| digest.update(part) }
      digest.digest
    end

    # Compares signatures in constant time.
    # @param expected [Array<String>] the signatures computed with each secret
    # @param given [String] the signature from the request
    # @return [Boolean] true when the given signature matches one of the expected ones
    def secure_match?(expected, given)
      expected.any? { |signature| ActiveSupport::SecurityUtils.secure_compare(signature, given) }
    end
  end
end
