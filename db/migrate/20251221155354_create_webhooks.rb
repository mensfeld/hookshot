class CreateWebhooks < ActiveRecord::Migration[8.1]
  def change
    create_table :webhooks do |t|
      t.json :headers, null: false, default: {}
      t.text :payload
      t.string :content_type, null: false
      t.string :source_ip, null: false
      t.datetime :received_at, null: false

      t.timestamps
    end

    add_index :webhooks, :received_at
  end
end
