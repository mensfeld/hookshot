class CreateTargets < ActiveRecord::Migration[8.1]
  def change
    create_table :targets do |t|
      t.string :name, null: false
      t.string :url, null: false
      t.boolean :active, null: false, default: true
      t.json :custom_headers, null: false, default: {}
      t.integer :timeout, null: false, default: 30

      t.timestamps
    end

    add_index :targets, :active
  end
end
