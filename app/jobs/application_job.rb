# frozen_string_literal: true

# Base class for all background jobs in the application.
# Provides shared configuration and behavior for all jobs.
class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError

  around_perform :capture_errors

  private

  def capture_errors
    yield
  rescue StandardError => e
    # EXCLUDE DispatchJob - those are operational errors tracked via Delivery model
    return if is_a?(DispatchJob)

    context = {
      job_class: self.class.name,
      job_id: job_id,
      queue_name: queue_name,
      arguments: arguments.map(&:to_s),
      executions: executions
    }

    Admin::ErrorCaptureJob.perform_later(
      e.class.name, e.message, e.backtrace || [], context
    ) rescue nil

    raise e  # Re-raise for ActiveJob retry logic
  end
end
