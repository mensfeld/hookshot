# Introduces endpoints (named inbound URLs) and moves the existing single receive URL behind a "default" endpoint
# that every existing target is attached to, so routing is unchanged after the migration.
class CreateEndpoints < ActiveRecord::Migration[8.1]
  def up
    create_table :endpoints do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.boolean :active, null: false, default: true

      t.timestamps
    end
    add_index :endpoints, :slug, unique: true

    create_table :endpoint_targets do |t|
      t.references :endpoint, null: false, foreign_key: true, index: false
      t.references :target, null: false, foreign_key: true

      t.timestamps
    end
    add_index :endpoint_targets, %i[endpoint_id target_id], unique: true

    add_reference :webhooks, :endpoint, foreign_key: true

    backfill_default_endpoint
  end

  def down
    remove_reference :webhooks, :endpoint, foreign_key: true
    drop_table :endpoint_targets
    drop_table :endpoints
  end

  private

  # Plain SQL so the migration does not depend on application models.
  def backfill_default_endpoint
    now = connection.quote(Time.current)

    execute <<~SQL
      INSERT INTO endpoints (name, slug, active, created_at, updated_at)
      VALUES ('Default', 'default', #{connection.quoted_true}, #{now}, #{now})
    SQL
    default_id = select_value("SELECT id FROM endpoints WHERE slug = 'default'")

    execute <<~SQL
      INSERT INTO endpoint_targets (endpoint_id, target_id, created_at, updated_at)
      SELECT #{default_id}, id, #{now}, #{now} FROM targets
    SQL
    execute "UPDATE webhooks SET endpoint_id = #{default_id}"
  end
end
