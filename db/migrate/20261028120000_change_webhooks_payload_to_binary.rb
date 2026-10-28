# Stores webhook bodies as raw bytes so they are relayed byte for byte.
class ChangeWebhooksPayloadToBinary < ActiveRecord::Migration[8.1]
  def up
    change_column :webhooks, :payload, :binary
  end

  def down
    change_column :webhooks, :payload, :text
  end
end
