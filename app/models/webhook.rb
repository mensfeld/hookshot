# frozen_string_literal: true

# Represents an incoming webhook received by the system.
# Stores the original headers, payload, and metadata from the request, and the endpoint that received it.
# Associated deliveries track the dispatch status to each configured target.
class Webhook < ApplicationRecord
  belongs_to :endpoint, optional: true
  has_many :deliveries, dependent: :destroy

  validates :content_type, :source_ip, :received_at, presence: true

  scope :today, -> { where("received_at >= ?", Time.current.beginning_of_day) }
  scope :older_than, ->(days) { where("received_at < ?", days.days.ago) }
  scope :for_endpoint, ->(endpoint_id) { endpoint_id.present? ? where(endpoint_id: endpoint_id) : all }
  scope :search_text, ->(term) {
    return all if term.blank?

    where(
      "json_quote(headers) LIKE ? OR payload LIKE ?",
      "%#{sanitize_sql_like(term)}%",
      "%#{sanitize_sql_like(term)}%"
    )
  }

  # Returns the size of the payload in bytes.
  # @return [Integer] payload size in bytes, or 0 if payload is nil
  def payload_size
    payload&.bytesize || 0
  end

  # Returns the payload as valid UTF-8 for display, with invalid bytes replaced by U+FFFD.
  # The stored payload stays raw bytes; only this copy is scrubbed.
  # @return [String] a valid UTF-8 copy of the payload ("" when nil)
  def display_payload
    payload.to_s.dup.force_encoding(Encoding::UTF_8).scrub
  end

  # Tells whether the stored payload is valid UTF-8 text.
  # @return [Boolean] true when display_payload shows the body unchanged
  def utf8_payload?
    payload.to_s.dup.force_encoding(Encoding::UTF_8).valid_encoding?
  end

  # Returns dispatch statistics for this webhook.
  # @return [Hash] hash containing :success and :total delivery counts
  def dispatch_stats
    total = deliveries.count
    success = deliveries.success.count
    { success: success, total: total }
  end
end
