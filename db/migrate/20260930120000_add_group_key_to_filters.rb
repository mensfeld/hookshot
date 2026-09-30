class AddGroupKeyToFilters < ActiveRecord::Migration[8.1]
  def change
    add_column :filters, :group_key, :string, null: false, default: "default"
    add_index :filters, %i[target_id group_key]
  end
end
