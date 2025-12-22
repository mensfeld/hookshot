# frozen_string_literal: true

# Provides HTTP Basic Authentication for admin controllers.
# Credentials are configured via environment variables.
module Authenticatable
  extend ActiveSupport::Concern

  included do
    before_action :authenticate
  end

  private

  # Performs HTTP Basic Authentication.
  # @return [void] renders 401 if authentication fails
  def authenticate
    authenticate_or_request_with_http_basic("Hookshot") do |user, password|
      ActiveSupport::SecurityUtils.secure_compare(user, hookshot_user) &&
        ActiveSupport::SecurityUtils.secure_compare(password, hookshot_password)
    end
  end

  # Returns the configured admin username.
  # @return [String] username from HOOKSHOT_USER env var
  def hookshot_user
    ENV.fetch("HOOKSHOT_USER", "admin")
  end

  # Returns the configured admin password.
  # @return [String] password from HOOKSHOT_PASSWORD env var
  def hookshot_password
    ENV.fetch("HOOKSHOT_PASSWORD", "changeme")
  end
end
