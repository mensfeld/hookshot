# frozen_string_literal: true

# Namespace for admin controllers.
module Admin
  # Base controller for all admin controllers.
  # Provides authentication, layout, and shared statistics.
  class AdminController < ApplicationController
    include Authenticatable

    layout "admin"

    helper_method :stats

    private

    # Returns dashboard statistics.
    # @return [Hash] stats including webhooks_today, success_rate, and pending
    def stats
      @stats ||= {
        webhooks_today: Webhook.today.count,
        success_rate: calculate_success_rate,
        pending: Delivery.pending.count
      }
    end

    # Calculates the success rate for the last 24 hours.
    # @return [Float] success rate percentage (0-100)
    def calculate_success_rate
      recent = Delivery.recent_24h.where.not(status: :filtered)
      total = recent.count
      return 100.0 if total.zero?

      (recent.success.count.to_f / total * 100).round(1)
    end
  end
end
