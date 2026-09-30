# frozen_string_literal: true

# Represents a filter rule for a target. Filters determine which webhooks should be delivered to a target based on
# header or payload content matching.
#
# Filters are organized into groups via +group_key+. Within a group all filters must match (AND), and a webhook is
# delivered when any group matches in full (OR). Filters without an explicit group share the default group, which
# keeps a target with ungrouped filters behaving as a plain AND of all its filters.
class Filter < ApplicationRecord
  # Group key assigned to filters that do not specify one.
  DEFAULT_GROUP_KEY = "default"

  # Maximum length of a group key.
  GROUP_KEY_MAX_LENGTH = 100

  belongs_to :target

  enum :filter_type, { header: 0, payload: 1 }
  enum :operator, { exists: 0, equals: 1, matches: 2 }

  validates :filter_type, :field, :operator, presence: true
  validates :value, presence: true, unless: -> { exists? }
  validates :group_key, presence: true, length: { maximum: GROUP_KEY_MAX_LENGTH }

  normalizes :group_key, with: ->(key) { key.to_s.strip.presence || DEFAULT_GROUP_KEY }, apply_to_nil: true

  # Returns a human-readable description of the filter.
  # @return [String] description of what the filter matches
  def description
    case operator
    when "exists"
      "#{filter_type.capitalize} '#{field}' must exist"
    when "equals"
      "#{filter_type.capitalize} '#{field}' equals '#{value}'"
    when "matches"
      "#{filter_type.capitalize} '#{field}' matches '#{value}'"
    end
  end

  # Checks whether this filter belongs to the implicit default group.
  # @return [Boolean] true if the filter is in the default group
  def default_group?
    group_key == DEFAULT_GROUP_KEY
  end
end
