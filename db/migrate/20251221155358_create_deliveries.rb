class CreateDeliveries < ActiveRecord::Migration[8.1]
  def change
    create_table :deliveries do |t|
      t.references :webhook, null: false, foreign_key: true
      t.references :target, null: false, foreign_key: true
      t.integer :status, null: false, default: 0
      t.integer :status_code
      t.text :response_body
      t.string :error_message
      t.integer :attempts, null: false, default: 0
      t.datetime :dispatched_at

      t.timestamps
    end

    add_index :deliveries, %i[webhook_id target_id]
    add_index :deliveries, :status
    add_index :deliveries, :created_at
  end
end
