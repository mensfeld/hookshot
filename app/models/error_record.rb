# frozen_string_literal: true

# Represents an application error captured by the error tracking system.
# Errors are deduplicated by fingerprint and track occurrence counts.
class ErrorRecord < ApplicationRecord
  validates :error_class, presence: true
  validates :fingerprint, presence: true, uniqueness: true

  scope :unresolved, -> { where(resolved_at: nil) }
  scope :resolved, -> { where.not(resolved_at: nil) }
  scope :recent_first, -> { order(last_occurred_at: :desc) }

  # Marks the error as resolved.
  # @return [Boolean] whether the update succeeded
  def resolve!
    update(resolved_at: Time.current)
  end

  # Marks the error as unresolved.
  # @return [Boolean] whether the update succeeded
  def unresolve!
    update(resolved_at: nil)
  end

  # Returns the first 20 lines of the backtrace.
  # @return [Array<String>] backtrace lines
  def backtrace_lines
    backtrace.to_s.split("\n").take(20)
  end

  # Checks if the error is resolved.
  # @return [Boolean] true if resolved
  def resolved?
    resolved_at.present?
  end
end
