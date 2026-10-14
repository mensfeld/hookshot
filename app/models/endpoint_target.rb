# frozen_string_literal: true

# Attaches a target to an endpoint: webhooks received by the endpoint are forwarded to the target.
class EndpointTarget < ApplicationRecord
  belongs_to :endpoint
  belongs_to :target

  validates :target_id, uniqueness: { scope: :endpoint_id }
end
