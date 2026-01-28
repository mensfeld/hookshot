module Admin
  # Background job for capturing application errors asynchronously.
  # Prevents error capture failures from affecting the main application flow.
  class ErrorCaptureJob < ApplicationJob
    queue_as :default
    discard_on StandardError  # Prevent retry loops

    # Captures an error by reconstructing the exception and calling the capture service.
    # @param error_class [String] the name of the exception class
    # @param error_message [String] the exception message
    # @param error_backtrace [Array<String>] the exception backtrace lines
    # @param context [Hash] additional context about the error
    # @return [void]
    def perform(error_class, error_message, error_backtrace, context = {})
      exception = build_exception(error_class, error_message, error_backtrace)
      Admin::Errors::Capture.call(exception, context: context)
    end

    private

    # Builds a synthetic exception object from string components.
    # @param error_class [String] the name of the exception class
    # @param error_message [String] the exception message
    # @param error_backtrace [Array<String>] the exception backtrace lines
    # @return [Exception] the reconstructed exception
    def build_exception(error_class, error_message, error_backtrace)
      # Create a synthetic exception object
      exception_class = begin
        error_class.constantize
      rescue NameError
        StandardError
      end

      exception = exception_class.new(error_message)
      exception.set_backtrace(error_backtrace)
      exception
    end
  end
end
