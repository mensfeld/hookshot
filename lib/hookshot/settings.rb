# frozen_string_literal: true

# Namespace for the Hookshot gem.
module Hookshot
  # Numeric settings read from the environment. Each must be a positive base-10 integer (underscores allowed, as in
  # `1_000_000`); an unset variable keeps its default. Checked once at boot, so a bad value stops Hookshot from
  # starting instead of deleting every webhook, rejecting every body or stopping deliveries.
  module Settings
    # Default value of each setting when its variable is unset.
    DEFAULTS = {
      "RETENTION_DAYS" => 30,
      "MAX_PAYLOAD_SIZE" => 1_048_576,
      "JOB_CONCURRENCY" => 1
    }.freeze

    # Digits only, optionally grouped with underscores; no sign, whitespace, decimals or units.
    FORMAT = /\A\d+(?:_\d+)*\z/

    # Raised when a setting is not a positive integer.
    class InvalidError < StandardError; end

    class << self
      # @return [Integer] days to keep webhooks before cleanup
      def retention_days
        fetch("RETENTION_DAYS")
      end

      # @return [Integer] maximum webhook body size in bytes
      def max_payload_size
        fetch("MAX_PAYLOAD_SIZE")
      end

      # @return [Integer] Solid Queue worker processes for the default queue
      def job_concurrency
        fetch("JOB_CONCURRENCY")
      end

      # Checks every setting.
      # @return [void]
      # @raise [InvalidError] when a setting is not a positive integer
      def validate!
        DEFAULTS.each_key { |name| fetch(name) }
      end

      private

      # @param name [String] environment variable name
      # @return [Integer] the variable's value, or its default when unset
      # @raise [InvalidError] when the value is not a positive integer
      def fetch(name)
        value = ENV.fetch(name) { return DEFAULTS.fetch(name) }
        integer = Integer(value, 10) if value.match?(FORMAT)
        return integer if integer&.positive?

        raise InvalidError, "#{name} must be a positive integer, got #{value.inspect}"
      end
    end
  end
end
