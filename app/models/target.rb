# frozen_string_literal: true

# Represents a destination endpoint for webhook delivery.
# Targets have associated filters that determine which webhooks are delivered.
class Target < ApplicationRecord
  has_many :filters, dependent: :destroy
  has_many :deliveries, dependent: :nullify

  validates :name, :url, presence: true
  validates :url, format: { with: URI::RFC2396_PARSER.make_regexp(%w[http https]), message: "must be a valid HTTP(S) URL" }
  validates :timeout, numericality: { greater_than: 0, less_than_or_equal_to: 300 }

  scope :active, -> { where(active: true) }

  # A new filter row is dropped when the user typed nothing into it (no field and no value). We cannot rely on
  # +:all_blank+ because +group_key+, +filter_type+ and +operator+ always arrive with values from the form. A partially
  # filled row (e.g. a value without a field) is kept so validation reports it instead of silently discarding it.
  # Existing filters are never rejected, so blanking the field of a saved filter also surfaces a validation error.
  accepts_nested_attributes_for :filters, allow_destroy: true,
    reject_if: ->(attrs) { attrs["id"].blank? && attrs["field"].blank? && attrs["value"].blank? }

  # Calculates the success rate for deliveries in the last 24 hours.
  # @return [Float] percentage of successful deliveries (0-100)
  def success_rate_24h
    recent = deliveries.recent_24h
    total = recent.count
    return 0 if total.zero?

    (recent.success.count.to_f / total * 100).round(1)
  end

  # Groups filters by their group key. Within a group all filters must match; across groups any group may match.
  # Groups are ordered by key and filters keep their original order within a group.
  # @return [Hash{String => Array<Filter>}] filters keyed by group key
  def filter_groups
    filters
      .reject(&:marked_for_destruction?)
      .group_by(&:group_key)
      .sort_by { |key, _| key }
      .to_h
  end

  # Returns the number of filters associated with this target.
  # @return [Integer] count of filters
  def filter_count
    filters.count
  end
end
