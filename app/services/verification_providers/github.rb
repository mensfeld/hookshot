# frozen_string_literal: true

module VerificationProviders
  # Verifies GitHub webhooks: +X-Hub-Signature-256+ carries +sha256=+ and the hex HMAC-SHA256 of the raw body.
  class Github < Base
    # Header GitHub puts the signature in.
    HEADER = "X-Hub-Signature-256"

    # Prefix GitHub puts before the hex digest.
    PREFIX = "sha256="

    # @return [String] the provider name
    def self.label
      "GitHub"
    end

    # @param request [ActionDispatch::Request] the inbound webhook request
    # @return [Boolean] true when the signature matches one computed with any secret
    def verified?(request)
      signature = request.headers[HEADER].to_s.strip
      return false unless signature.start_with?(PREFIX)

      expected = secrets.map { |secret| PREFIX + hmac("sha256", secret, request.raw_post).unpack1("H*") }
      secure_match?(expected, signature.downcase)
    end
  end
end
