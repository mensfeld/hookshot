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
  # Human-readable operator names used in forms.
  OPERATOR_LABELS = {
    "exists" => "Exists",
    "equals" => "Equals",
    "matches" => "Matches (wildcard)",
    "regex" => "Matches regex"
  }.freeze

  # Maximum time in seconds a single regex match may take. Filters run while the webhook request is handled, so a
  # pathological pattern must not be able to stall it.
  REGEX_TIMEOUT = 0.1

  enum :operator, { exists: 0, equals: 1, matches: 2, regex: 3 }

  validates :filter_type, :field, :operator, presence: true
  validates :value, presence: true, unless: -> { exists? }
  validates :group_key, presence: true, length: { maximum: GROUP_KEY_MAX_LENGTH }
  validate :value_must_be_valid_regex, if: :regex?

  normalizes :group_key, with: ->(key) { key.to_s.strip.presence || DEFAULT_GROUP_KEY }, apply_to_nil: true

  # Operator choices for select inputs.
  # @return [Array<Array(String, String)>] label and value pairs
  def self.operator_options
    operators.keys.map { |operator| [ OPERATOR_LABELS.fetch(operator), operator ] }
  end

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
    when "regex"
      "#{filter_type.capitalize} '#{field}' matches regex /#{value}/"
    end
  end

  # Compiles the filter value as a regular expression with a match timeout.
  # @return [Regexp] the compiled regular expression
  # @raise [RegexpError] when the value is not a valid regular expression
  def compiled_regex
    Regexp.new(value.to_s, timeout: REGEX_TIMEOUT)
  end

  # Checks whether this filter belongs to the implicit default group.
  # @return [Boolean] true if the filter is in the default group
  def default_group?
    group_key == DEFAULT_GROUP_KEY
  end

  private

  # Adds a validation error when a regex filter's value does not compile.
  # @return [void]
  def value_must_be_valid_regex
    return if value.blank?

    compiled_regex
  rescue RegexpError => e
    errors.add(:value, "is not a valid regular expression (#{e.message})")
  end
end
