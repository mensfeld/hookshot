module Admin
  class ErrorCaptureJob < ApplicationJob
    queue_as :default
    discard_on StandardError  # Prevent retry loops

    def perform(error_class, error_message, error_backtrace, context = {})
      exception = build_exception(error_class, error_message, error_backtrace)
      Admin::Errors::Capture.call(exception, context: context)
    end

    private

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
