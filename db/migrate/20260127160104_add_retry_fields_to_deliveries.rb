# Adds retry tracking fields to deliveries table for enhanced retry strategy.
# Supports hybrid retry approach with ActiveJob and recurring job phases.
class AddRetryFieldsToDeliveries < ActiveRecord::Migration[8.1]
  # Adds next_retry_at, last_retry_at, and retry_stage columns
  # @return [void]
  def change
    add_column :deliveries, :next_retry_at, :datetime
    add_column :deliveries, :last_retry_at, :datetime
    add_column :deliveries, :retry_stage, :integer, default: 0, null: false

    add_index :deliveries, [ :status, :next_retry_at ],
      where: "status = 2 AND next_retry_at IS NOT NULL",
      name: "index_deliveries_on_failed_with_retry"
  end
end
