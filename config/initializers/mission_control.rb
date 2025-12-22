# frozen_string_literal: true

require "mission_control/jobs"

Rails.application.configure do
  # Disable Mission Control's built-in auth - we'll use the app's auth
  config.mission_control.jobs.http_basic_auth_enabled = false
end

# Add custom authentication via the application's existing auth
Rails.application.config.after_initialize do
  MissionControl::Jobs::ApplicationController.class_eval do
    include Authenticatable

    before_action :authenticate!
  end
end
