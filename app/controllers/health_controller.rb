# frozen_string_literal: true

# Health check endpoint for monitoring and container orchestration.
# Returns the application status and database connectivity.
class HealthController < ApplicationController
  # Returns the health status of the application.
  # @return [void] renders JSON with status, timestamp, and database health
  def show
    render json: {
      status: "ok",
      timestamp: Time.current.iso8601,
      database: database_healthy?
    }
  end

  private

  # Checks if the database connection is healthy.
  # @return [Boolean] true if database is accessible
  def database_healthy?
    ActiveRecord::Base.connection.execute("SELECT 1")
    true
  rescue StandardError
    false
  end
end
