# frozen_string_literal: true

# Helper methods for rendering endpoints.
module EndpointsHelper
  # Returns the URL senders post webhooks to for an endpoint.
  # @param endpoint [Endpoint] endpoint whose receive URL to build
  # @return [String] the plain /webhooks/receive URL for the default endpoint, otherwise /webhooks/receive/:slug
  def endpoint_receive_url(endpoint)
    endpoint.default? ? webhooks_receive_url : webhooks_receive_endpoint_url(endpoint.slug)
  end
end
