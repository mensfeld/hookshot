# frozen_string_literal: true

# Represents a destination endpoint for webhook delivery.
# Targets have associated filters that determine which webhooks are delivered.
class Target < ApplicationRecord
  has_many :filters, dependent: :destroy
  has_many :deliveries, dependent: :nullify

  validates :name, :url, presence: true
  validates :url, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), message: "must be a valid HTTP(S) URL" }
  validates :timeout, numericality: { greater_than: 0, less_than_or_equal_to: 300 }

  scope :active, -> { where(active: true) }

  accepts_nested_attributes_for :filters, allow_destroy: true, reject_if: :all_blank

  # Calculates the success rate for deliveries in the last 24 hours.
  # @return [Float] percentage of successful deliveries (0-100)
  def success_rate_24h
    recent = deliveries.recent_24h
    total = recent.count
    return 0 if total.zero?

    (recent.success.count.to_f / total * 100).round(1)
  end

  # Returns the number of filters associated with this target.
  # @return [Integer] count of filters
  def filter_count
    filters.count
  end
end
