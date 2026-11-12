# frozen_string_literal: true

# Helper methods for rendering endpoints.
module EndpointsHelper
  # Returns the URL senders post webhooks to for an endpoint.
  # @param endpoint [Endpoint] endpoint whose receive URL to build
  # @return [String] the plain /webhooks/receive URL for the default endpoint, otherwise /webhooks/receive/:slug
  def endpoint_receive_url(endpoint)
    endpoint.default? ? webhooks_receive_url : webhooks_receive_endpoint_url(endpoint.slug)
  end

  # Returns the name of the endpoint's signature verification.
  # @param endpoint [Endpoint] endpoint to describe
  # @return [String, nil] the provider name (its key when no longer registered), or nil when the endpoint verifies no
  #   signatures
  def verification_provider_label(endpoint)
    return unless endpoint.verifies_signatures?

    VerificationProviders.fetch(endpoint.verification_provider)&.label || endpoint.verification_provider
  end

  # Returns the registered verification providers as select options.
  # @return [Array<Array(String, String)>] provider name and key pairs
  def verification_provider_options
    VerificationProviders.all.map { |key, provider| [ provider.label, key ] }
  end
end
