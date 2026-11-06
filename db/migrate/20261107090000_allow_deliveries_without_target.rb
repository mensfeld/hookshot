# Lets a delivery outlive its target: deleting a target keeps its delivery history (shown as "Deleted Target")
# instead of failing on the NOT NULL constraint that the target's dependent: :nullify ran into.
class AllowDeliveriesWithoutTarget < ActiveRecord::Migration[8.1]
  def up
    change_column_null :deliveries, :target_id, true
  end

  # Deliveries of deleted targets cannot satisfy the constraint again, so rolling back removes them.
  def down
    execute "DELETE FROM deliveries WHERE target_id IS NULL"
    change_column_null :deliveries, :target_id, false
  end
end
