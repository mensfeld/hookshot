# frozen_string_literal: true

# Helper methods for rendering targets and their filter groups.
module TargetsHelper
  # Builds a one-line, human-readable summary of a target's filter logic.
  # Filters within a group are joined with AND and groups are joined with OR.
  # @param target [Target] the target whose filters to summarize
  # @return [String] summary of the filter logic
  def filter_logic_summary(target)
    groups = target.filter_groups
    return "Delivers every webhook (no filters)" if groups.empty?

    clauses = groups.map do |group_key, filters|
      conditions = filters.map(&:description).join(" AND ")
      groups.size > 1 ? "[#{group_key}] (#{conditions})" : conditions
    end

    "Delivers if #{clauses.join(' OR ')}"
  end
end
