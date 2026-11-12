# frozen_string_literal: true

# Registry of the providers an endpoint can verify inbound webhook signatures with. Hookshot ships the GitHub provider;
# an application adds its own by subclassing VerificationProviders::Base and registering it in an initializer.
module VerificationProviders
  @providers = {}

  class << self
    # Registers a provider under a key, replacing any provider registered under the same key.
    # @param key [String, Symbol] the name stored on endpoints that use the provider
    # @param provider [Class<VerificationProviders::Base>] the provider class
    # @return [void]
    def register(key, provider)
      @providers[key.to_s] = provider
    end

    # Returns the provider registered under a key.
    # @param key [String, nil] the provider key
    # @return [Class<VerificationProviders::Base>, nil] the provider class, or nil when none is registered
    def fetch(key)
      @providers[key.to_s]
    end

    # Returns every registered provider.
    # @return [Hash{String => Class<VerificationProviders::Base>}] provider classes by key
    def all
      @providers.dup
    end
  end
end
