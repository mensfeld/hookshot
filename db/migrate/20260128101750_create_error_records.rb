# Creates the error_records table for error tracking system.
class CreateErrorRecords < ActiveRecord::Migration[7.2]
  # Creates error_records table with fingerprint-based deduplication indexes.
  def change
    create_table :error_records do |t|
      t.string :error_class, null: false
      t.text :message
      t.text :backtrace
      t.json :context, default: {}, null: false
      t.string :fingerprint, null: false
      t.integer :occurrences_count, null: false, default: 1
      t.datetime :first_occurred_at, null: false
      t.datetime :last_occurred_at, null: false
      t.datetime :resolved_at
      t.timestamps
    end

    add_index :error_records, :fingerprint, unique: true
    add_index :error_records, :resolved_at
    add_index :error_records, :last_occurred_at
    add_index :error_records, [ :resolved_at, :last_occurred_at ]
  end
end
