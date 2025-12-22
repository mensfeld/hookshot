# frozen_string_literal: true

# Represents an incoming webhook received by the system.
# Stores the original headers, payload, and metadata from the request.
# Associated deliveries track the dispatch status to each configured target.
class Webhook < ApplicationRecord
  has_many :deliveries, dependent: :destroy

  validates :content_type, :source_ip, :received_at, presence: true

  scope :today, -> { where("received_at >= ?", Time.current.beginning_of_day) }
  scope :older_than, ->(days) { where("received_at < ?", days.days.ago) }

  # Returns the size of the payload in bytes.
  # @return [Integer] payload size in bytes, or 0 if payload is nil
  def payload_size
    payload&.bytesize || 0
  end

  # Returns dispatch statistics for this webhook.
  # @return [Hash] hash containing :success and :total delivery counts
  def dispatch_stats
    total = deliveries.count
    success = deliveries.success.count
    { success: success, total: total }
  end
end
