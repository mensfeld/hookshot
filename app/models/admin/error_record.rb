module Admin
  class ErrorRecord < ApplicationRecord
    validates :error_class, presence: true
    validates :fingerprint, presence: true, uniqueness: true

    scope :unresolved, -> { where(resolved_at: nil) }
    scope :resolved, -> { where.not(resolved_at: nil) }
    scope :recent_first, -> { order(last_occurred_at: :desc) }

    def resolve!
      update(resolved_at: Time.current)
    end

    def unresolve!
      update(resolved_at: nil)
    end

    def backtrace_lines
      backtrace.to_s.split("\n").take(20)
    end

    def resolved?
      resolved_at.present?
    end
  end
end
