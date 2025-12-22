# frozen_string_literal: true

require "mission_control/jobs"

Rails.application.configure do
  config.mission_control.jobs.http_basic_auth_enabled = true
  config.mission_control.jobs.http_basic_auth_user = ENV.fetch("HOOKSHOT_USER", "admin")
  config.mission_control.jobs.http_basic_auth_password = ENV.fetch("HOOKSHOT_PASSWORD", "changeme")
end
