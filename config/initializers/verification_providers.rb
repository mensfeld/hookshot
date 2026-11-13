# frozen_string_literal: true

# Signature verification providers endpoints can use. Register your own here, e.g.
# VerificationProviders.register("stripe", VerificationProviders::Stripe).
Rails.application.config.to_prepare do
  VerificationProviders.register("github", VerificationProviders::Github)
end
