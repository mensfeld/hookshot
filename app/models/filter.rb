# frozen_string_literal: true

# Represents a filter rule for a target.
# Filters determine which webhooks should be delivered to a target based on
# header or payload content matching.
class Filter < ApplicationRecord
  belongs_to :target

  enum :filter_type, { header: 0, payload: 1 }
  enum :operator, { exists: 0, equals: 1, matches: 2 }

  validates :filter_type, :field, :operator, presence: true
  validates :value, presence: true, unless: -> { exists? }

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
end
