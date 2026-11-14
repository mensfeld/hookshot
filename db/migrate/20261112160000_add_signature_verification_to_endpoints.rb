# Per-endpoint verification of inbound webhook signatures. Endpoints without a provider accept every request as before.
class AddSignatureVerificationToEndpoints < ActiveRecord::Migration[8.1]
  def change
    change_table :endpoints, bulk: true do |t|
      t.string :verification_provider
      t.text :signing_secrets
      t.integer :verification_failures_count, default: 0, null: false
      t.datetime :last_verification_failed_at
    end
  end
end
