# frozen_string_literal: true

# Helper methods for rendering endpoints.
module EndpointsHelper
  # Names of the signature verification presets, as shown in the admin.
  SIGNATURE_PRESET_LABELS = {
    "github" => "GitHub", "stripe" => "Stripe", "slack" => "Slack", "shopify" => "Shopify", "generic" => "Generic HMAC"
  }.freeze

  # Returns the URL senders post webhooks to for an endpoint.
  # @param endpoint [Endpoint] endpoint whose receive URL to build
  # @return [String] the plain /webhooks/receive URL for the default endpoint, otherwise /webhooks/receive/:slug
  def endpoint_receive_url(endpoint)
    endpoint.default? ? webhooks_receive_url : webhooks_receive_endpoint_url(endpoint.slug)
  end

  # Returns the name of the endpoint's signature verification.
  # @param endpoint [Endpoint] endpoint to describe
  # @return [String, nil] the preset name, or nil when the endpoint verifies no signatures
  def signature_preset_label(endpoint)
    SIGNATURE_PRESET_LABELS[endpoint.signature_preset] if endpoint.verifies_signatures?
  end
end
