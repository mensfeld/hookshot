module Admin
  module Errors
    # Subscriber for Rails error reporting pipeline.
    # Captures application errors and stores them in the database.
    class Subscriber
      # Reports an error to the error tracking system.
      #
      # @param error [Exception] the error that occurred
      # @param handled [Boolean] whether the error was handled
      # @param severity [Symbol] error severity (:error, :warning, :info)
      # @param context [Hash] additional context about the error
      # @param source [String] where the error originated
      # @return [ErrorRecord, nil] the created/updated error record, or nil if capture failed
      def report(error, handled:, severity:, context:, source:)
        # Only capture errors, not warnings or info
        return unless severity == :error

        # Skip DispatchJob errors - those are operational cases tracked via Delivery model
        return if dispatch_job_error?(context)

        # Skip in test environment unless explicitly enabled
        return if Rails.env.test? && !context[:force_capture]

        Admin::ErrorCaptureJob.perform_later(
          error.class.name,
          error.message,
          error.backtrace || [],
          build_context(context, source)
        )
      rescue StandardError => e
        Rails.logger.error("[ErrorSubscriber] Failed to queue error capture: #{e.message}")
        nil
      end

      private

      # Checks if the error originated from a DispatchJob.
      # @param context [Hash] the error context
      # @return [Boolean] true if this is a DispatchJob error
      def dispatch_job_error?(context)
        context[:job]&.is_a?(DispatchJob) ||
          context.dig(:job, :class) == "DispatchJob"
      end

      # Builds the context hash for the capture job.
      # @param context [Hash] the original error context
      # @param source [String] the error source identifier
      # @return [Hash] the structured context
      def build_context(context, source)
        {
          source: source,
          job: extract_job_context(context),
          controller: extract_controller_context(context),
          additional: context.except(:job, :controller, :force_capture)
        }.compact
      end

      # Extracts job-related context information.
      # @param context [Hash] the error context
      # @return [Hash, nil] the job context or nil if not present
      def extract_job_context(context)
        return nil unless context[:job]

        job = context[:job]
        {
          class: job.class.name,
          queue: job.queue_name,
          arguments: job.arguments.map(&:to_s),
          executions: job.executions
        }
      end

      # Extracts controller-related context information.
      # @param context [Hash] the error context
      # @return [Hash, nil] the controller context or nil if not present
      def extract_controller_context(context)
        return nil unless context[:controller]

        {
          name: context[:controller],
          action: context[:action],
          params: context[:params]
        }
      end
    end
  end
end
