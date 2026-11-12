# frozen_string_literal: true

# A named inbound URL that receives webhooks (+POST /webhooks/receive/:slug+). Each endpoint forwards what it receives
# only to the targets attached to it, so a single sender can route different actions by posting to different URLs.
# The default endpoint backs the plain +POST /webhooks/receive+ URL; it can be deactivated but not removed or renamed.
# An endpoint with a verifier rejects requests whose signature does not match one of its secrets.
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

  # Verifier types an endpoint can use; nil verifies nothing.
  VERIFIERS = %w[hmac].freeze

  # Signature settings stored as nil instead of an empty string.
  OPTIONAL_SIGNATURE_SETTINGS = %i[
    signature_preset signature_header signature_algorithm signature_encoding signature_prefix signature_format
    signature_key timestamp_key signed_payload_template timestamp_header signing_secrets
  ].freeze

  # Every signature setting; all of them are cleared when verification is turned off.
  SIGNATURE_SETTINGS = (OPTIONAL_SIGNATURE_SETTINGS - %i[signature_preset] + %i[timestamp_tolerance]).freeze

  normalizes :slug, with: ->(slug) { slug.to_s.strip.downcase.gsub(/[\s_]+/, "-") }

  normalizes(*OPTIONAL_SIGNATURE_SETTINGS, with: ->(value) { value.presence })

  before_validation :derive_slug_from_name, if: -> { slug.blank? && name.present? }
  before_validation :apply_signature_preset

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true, length: { maximum: SLUG_MAX_LENGTH },
    format: { with: SLUG_FORMAT, message: "may only contain lowercase letters, digits and single dashes" }
  validate :default_slug_unchanged, on: :update

  with_options if: :verifies_signatures? do
    validates :verifier, inclusion: { in: VERIFIERS }
    validates :signature_preset, inclusion: { in: SignatureVerifier::PRESETS.keys }
    validates :signature_header, presence: true
    validates :signature_algorithm, inclusion: { in: SignatureVerifier::ALGORITHMS }
    validates :signature_encoding, inclusion: { in: SignatureVerifier::ENCODINGS }
    validates :signature_format, inclusion: { in: SignatureVerifier::FORMATS }
    validates :signature_key, presence: { message: "is required for a key=value signature header" },
      if: -> { signature_format == "key_value" }
    validates :timestamp_tolerance, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
    validate :signing_secrets_present
    validate :signed_payload_template_valid
    validate :timestamp_source_present
  end

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

  # Checks whether requests to this endpoint must carry a valid signature.
  # @return [Boolean] true when a verifier is set
  def verifies_signatures?
    verifier.present?
  end

  # Returns the configured signing secrets; a request signed with any of them is accepted.
  # @return [Array<String>] one secret per non-blank line of +signing_secrets+
  def signing_secrets_list
    signing_secrets.to_s.lines.map(&:strip).reject(&:empty?)
  end

  # Counts a rejected request without loading or locking the row.
  # @return [void]
  def record_verification_failure!
    self.class.where(id: id).update_all(
      [ "verification_failures_count = verification_failures_count + 1, last_verification_failed_at = ?", Time.current ]
    )
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

  # Sets the verifier from the preset and fills in a named preset's settings; "generic" keeps the entered ones and
  # fills only the blank ones it needs. Without a preset every setting is cleared, so the row carries no strings.
  # @return [void]
  def apply_signature_preset
    self.verifier = signature_preset ? "hmac" : nil
    return assign_attributes(SIGNATURE_SETTINGS.index_with(nil)) unless signature_preset

    settings = SignatureVerifier::PRESETS[signature_preset]
    if settings&.any?
      assign_attributes(SignatureVerifier::PRESET_RESETS.merge(settings))
    else
      SignatureVerifier::GENERIC_DEFAULTS.each { |name, value| self[name] = value if self[name].blank? }
    end
  end

  # Adds an error when signature verification is on without a secret.
  # @return [void]
  def signing_secrets_present
    errors.add(:signing_secrets, "must contain at least one secret") if signing_secrets_list.empty?
  end

  # Adds an error when the signed-content template contains an unknown placeholder.
  # @return [void]
  def signed_payload_template_valid
    return unless signed_payload_template.to_s.gsub(SignatureVerifier::PLACEHOLDER, "").match?(/[{}]/)

    errors.add(:signed_payload_template, "may only use {body}, {timestamp} and {header:Name}")
  end

  # Adds an error when a timestamp is signed or checked but no header or key carries it.
  # @return [void]
  def timestamp_source_present
    return unless timestamp_tolerance || signed_payload_template.to_s.include?("{timestamp}")
    return if timestamp_header || (signature_format == "key_value" && timestamp_key)

    errors.add(:timestamp_header, "is required when the template signs {timestamp} or a tolerance is set")
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
