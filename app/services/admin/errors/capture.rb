module Admin
  module Errors
    class Capture
      SENSITIVE_KEYS = %w[password token secret authorization api_key].freeze
      MAX_CONTEXT_SIZE = 10_240 # 10KB

      def self.call(exception, context: {})
        new(exception, context).call
      rescue StandardError => e
        Rails.logger.error("[ErrorCapture] Failed: #{e.message}")
        nil
      end

      def initialize(exception, context = {})
        @exception = exception
        @context = context
      end

      def call
        fingerprint = generate_fingerprint

        Admin::ErrorRecord.transaction do
          record = Admin::ErrorRecord.find_or_initialize_by(fingerprint: fingerprint)

          if record.new_record?
            record.assign_attributes(
              error_class: @exception.class.name,
              message: @exception.message,
              backtrace: clean_backtrace.join("\n"),
              context: sanitize_context,
              first_occurred_at: Time.current,
              last_occurred_at: Time.current,
              occurrences_count: 1
            )
          else
            record.increment!(:occurrences_count)
            record.update(
              last_occurred_at: Time.current,
              context: sanitize_context # Update with latest context
            )
          end

          record.save!
          record
        end
      rescue StandardError => e
        Rails.logger.error("[ErrorCapture] Transaction failed: #{e.message}")
        nil
      end

      private

      def generate_fingerprint
        cleaned_message = clean_message(@exception.message.to_s)
        raw = "#{@exception.class.name}:#{cleaned_message}"
        Digest::SHA256.hexdigest(raw)
      end

      def clean_message(message)
        message
          .gsub(/\b\d+\b/, 'N')                           # Numbers -> N
          .gsub(/\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/i, 'UUID')  # UUIDs
          .gsub(/0x[0-9a-f]+/i, '0xHEX')                  # Hex addresses
          .gsub(%r{/tmp/[^\s]+}, '/tmp/PATH')             # Temp paths
      end

      def clean_backtrace
        return [] unless @exception.backtrace

        @exception.backtrace
          .reject { |line| line.include?('/gems/') || line.include?('/rubygems/') }
          .take(50)
      end

      def sanitize_context
        sanitized = deep_sanitize(@context)
        json = sanitized.to_json

        if json.bytesize > MAX_CONTEXT_SIZE
          truncated = json[0...MAX_CONTEXT_SIZE]
          { truncated: true, data: truncated }
        else
          sanitized
        end
      end

      def deep_sanitize(obj)
        case obj
        when Hash
          obj.each_with_object({}) do |(key, value), result|
            if SENSITIVE_KEYS.any? { |sensitive| key.to_s.downcase.include?(sensitive) }
              result[key] = '[REDACTED]'
            else
              result[key] = deep_sanitize(value)
            end
          end
        when Array
          obj.map { |item| deep_sanitize(item) }
        when String
          obj.length > 1000 ? "#{obj[0...1000]}... [truncated]" : obj
        else
          obj
        end
      end
    end
  end
end
