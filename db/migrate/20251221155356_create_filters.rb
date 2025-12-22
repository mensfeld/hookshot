class CreateFilters < ActiveRecord::Migration[8.1]
  def change
    create_table :filters do |t|
      t.references :target, null: false, foreign_key: true
      t.integer :filter_type, null: false
      t.string :field, null: false
      t.integer :operator, null: false
      t.string :value

      t.timestamps
    end
  end
end
