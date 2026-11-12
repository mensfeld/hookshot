# Per-endpoint verification of inbound webhook signatures. Endpoints without a verifier accept every request as before.
class AddSignatureVerificationToEndpoints < ActiveRecord::Migration[8.1]
  def change
    change_table :endpoints, bulk: true do |t|
      t.string :verifier
      t.string :signature_preset
      t.string :signature_header
      t.string :signature_algorithm, default: "sha256", null: false
      t.string :signature_encoding, default: "hex", null: false
      t.string :signature_prefix
      t.string :signature_format, default: "plain", null: false
      t.string :signature_key
      t.string :timestamp_key
      t.string :signed_payload_template, default: "{body}", null: false
      t.string :timestamp_header
      t.integer :timestamp_tolerance
      t.text :signing_secrets
      t.integer :verification_failures_count, default: 0, null: false
      t.datetime :last_verification_failed_at
    end
  end
end
