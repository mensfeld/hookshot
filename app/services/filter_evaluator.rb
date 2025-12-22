# frozen_string_literal: true

# Evaluates filter rules against a webhook to determine if it passes.
# Supports header and payload filters with exists, equals, and matches operators.
class FilterEvaluator
  # Initializes a new filter evaluator.
  # @param webhook [Webhook] the webhook to evaluate
  # @param target [Target] the target whose filters to check
  def initialize(webhook, target)
    @webhook = webhook
    @target = target
  end

  # Checks if the webhook passes all filters for the target.
  # @return [Boolean] true if all filters pass or no filters exist
  def passes?
    @target.filters.all? { |filter| evaluate(filter) }
  end

  private

  # Evaluates a single filter against the webhook.
  # @param filter [Filter] the filter to evaluate
  # @return [Boolean] true if the filter condition is met
  def evaluate(filter)
    case filter.filter_type
    when "header" then evaluate_header(filter)
    when "payload" then evaluate_payload(filter)
    else false
    end
  end

  # Evaluates a header-based filter.
  # @param filter [Filter] the header filter to evaluate
  # @return [Boolean] true if the header matches the filter
  def evaluate_header(filter)
    value = find_header_value(filter.field)
    apply_operator(filter, value)
  end

  # Evaluates a payload-based filter.
  # @param filter [Filter] the payload filter to evaluate
  # @return [Boolean] true if the payload field matches the filter
  def evaluate_payload(filter)
    return false unless @webhook.payload.present?

    json = parse_json
    return false unless json

    value = extract_json_path(json, filter.field)
    apply_operator(filter, value)
  end

  # Finds a header value by field name, trying multiple formats.
  # @param field [String] the header field name to find
  # @return [String, nil] the header value or nil if not found
  def find_header_value(field)
    # Headers are stored with HTTP_ prefix and uppercase
    # Try exact match first, then normalized match
    @webhook.headers[field] ||
      @webhook.headers["HTTP_#{field.upcase.tr('-', '_')}"] ||
      @webhook.headers[field.upcase.tr("-", "_")]
  end

  # Applies the filter operator to a value.
  # @param filter [Filter] the filter containing the operator
  # @param value [Object] the value to check
  # @return [Boolean] true if the value matches the operator condition
  def apply_operator(filter, value)
    case filter.operator
    when "exists" then value.present?
    when "equals" then value.to_s == filter.value
    when "matches" then match_pattern?(value.to_s, filter.value)
    else false
    end
  end

  # Checks if a value matches a glob-style pattern.
  # @param value [String] the value to check
  # @param pattern [String] the pattern with optional wildcards
  # @return [Boolean] true if the value matches the pattern
  def match_pattern?(value, pattern)
    return false if pattern.blank?

    # Convert glob-style wildcards to regex
    regex = Regexp.new("\\A#{Regexp.escape(pattern).gsub('\*', '.*')}\\z", Regexp::IGNORECASE)
    value.match?(regex)
  rescue RegexpError
    false
  end

  # Parses the webhook payload as JSON.
  # @return [Hash, nil] parsed JSON or nil if parsing fails
  def parse_json
    JSON.parse(@webhook.payload)
  rescue JSON::ParserError
    nil
  end

  # Extracts a value from JSON using a simple JSONPath-like syntax.
  # @param json [Hash] the parsed JSON object
  # @param path [String] the path (e.g., "$.foo.bar")
  # @return [Object, nil] the extracted value or nil if not found
  def extract_json_path(json, path)
    # Simple JSONPath-like extraction: $.foo.bar -> ["foo"]["bar"]
    keys = path.sub(/^\$\.?/, "").split(".")
    keys.reduce(json) do |obj, key|
      return nil unless obj.is_a?(Hash)
      obj[key]
    end
  end
end
