# frozen_string_literal: true

# A named inbound URL that receives webhooks (+POST /webhooks/receive/:slug+). Each endpoint forwards what it receives
# only to the targets attached to it, so a single sender can route different actions by posting to different URLs.
# The default endpoint backs the plain +POST /webhooks/receive+ URL; it can be deactivated but not removed or renamed.
class Endpoint < ApplicationRecord
  # Slug of the endpoint behind the plain /webhooks/receive URL.
  DEFAULT_SLUG = "default"

  # Maximum length of a slug.
  SLUG_MAX_LENGTH = 64

  # Allowed slug format: lowercase letters and digits, separated by single dashes.
  SLUG_FORMAT = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/

  has_many :endpoint_targets, dependent: :destroy
  has_many :targets, through: :endpoint_targets
  has_many :webhooks, dependent: :nullify

  normalizes :slug, with: ->(slug) { slug.to_s.strip.downcase.gsub(/[\s_]+/, "-") }

  before_validation :derive_slug_from_name, if: -> { slug.blank? && name.present? }

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true, length: { maximum: SLUG_MAX_LENGTH },
    format: { with: SLUG_FORMAT, message: "may only contain lowercase letters, digits and single dashes" }
  validate :default_slug_unchanged, on: :update

  before_destroy :prevent_default_destroy

  scope :active, -> { where(active: true) }

  # Returns the default endpoint, creating it when missing (e.g. on a database built from the schema).
  # @return [Endpoint] the endpoint behind the plain /webhooks/receive URL
  def self.default
    find_by(slug: DEFAULT_SLUG) || create!(slug: DEFAULT_SLUG, name: "Default")
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    # Another request created it between the lookup and the insert
    find_by!(slug: DEFAULT_SLUG)
  end

  # Checks whether this is the default endpoint.
  # @return [Boolean] true for the endpoint behind the plain /webhooks/receive URL
  def default?
    slug_in_database == DEFAULT_SLUG || (new_record? && slug == DEFAULT_SLUG)
  end

  # Returns the number of webhooks received in the last 24 hours.
  # @return [Integer] count of recent webhooks
  def webhooks_count_24h
    webhooks.where("received_at >= ?", 24.hours.ago).count
  end

  # Returns when this endpoint last received a webhook.
  # @return [ActiveSupport::TimeWithZone, nil] time of the latest webhook or nil
  def last_received_at
    webhooks.maximum(:received_at)
  end

  private

  # Builds a slug from the name when none was given (e.g. "GitHub Deploys" becomes "github-deploys").
  # @return [void]
  def derive_slug_from_name
    self.slug = name.parameterize.first(SLUG_MAX_LENGTH).delete_suffix("-")
  end

  # Adds an error when the default endpoint's slug is changed.
  # @return [void]
  def default_slug_unchanged
    return unless slug_changed? && slug_was == DEFAULT_SLUG

    errors.add(:slug, "of the default endpoint cannot be changed")
  end

  # Aborts destroying the default endpoint.
  # @return [void]
  def prevent_default_destroy
    return unless default?

    errors.add(:base, "The default endpoint cannot be deleted")
    throw :abort
  end
end
