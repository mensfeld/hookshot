# frozen_string_literal: true

require "mission_control/jobs"

MissionControl::Jobs.http_basic_auth_enabled = true
MissionControl::Jobs.http_basic_auth_user = ENV.fetch("HOOKSHOT_USER", "admin")
MissionControl::Jobs.http_basic_auth_password = ENV.fetch("HOOKSHOT_PASSWORD", "changeme")
