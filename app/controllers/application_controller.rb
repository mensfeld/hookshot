# frozen_string_literal: true

# Base controller for all controllers in the application.
# Provides shared configuration and behavior.
class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  rescue_from StandardError, with: :capture_and_reraise if Rails.env.production?

  private

  def capture_and_reraise(exception)
    context = {
      controller: controller_name,
      action: action_name,
      params: params.to_unsafe_h.except(:password, :token, :secret),
      request_id: request.request_id,
      ip: request.remote_ip
    }

    Admin::ErrorCaptureJob.perform_later(
      exception.class.name,
      exception.message,
      exception.backtrace || [],
      context
    ) rescue nil

    raise exception  # Show error page
  end
end
