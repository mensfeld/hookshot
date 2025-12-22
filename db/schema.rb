# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2025_12_21_155358) do
  create_table "deliveries", force: :cascade do |t|
    t.integer "attempts", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "dispatched_at"
    t.string "error_message"
    t.text "response_body"
    t.integer "status", default: 0, null: false
    t.integer "status_code"
    t.integer "target_id", null: false
    t.datetime "updated_at", null: false
    t.integer "webhook_id", null: false
    t.index ["created_at"], name: "index_deliveries_on_created_at"
    t.index ["status"], name: "index_deliveries_on_status"
    t.index ["target_id"], name: "index_deliveries_on_target_id"
    t.index ["webhook_id", "target_id"], name: "index_deliveries_on_webhook_id_and_target_id"
    t.index ["webhook_id"], name: "index_deliveries_on_webhook_id"
  end

  create_table "filters", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "field", null: false
    t.integer "filter_type", null: false
    t.integer "operator", null: false
    t.integer "target_id", null: false
    t.datetime "updated_at", null: false
    t.string "value"
    t.index ["target_id"], name: "index_filters_on_target_id"
  end

  create_table "targets", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.json "custom_headers", default: {}, null: false
    t.string "name", null: false
    t.integer "timeout", default: 30, null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.index ["active"], name: "index_targets_on_active"
  end

  create_table "webhooks", force: :cascade do |t|
    t.string "content_type", null: false
    t.datetime "created_at", null: false
    t.json "headers", default: {}, null: false
    t.text "payload"
    t.datetime "received_at", null: false
    t.string "source_ip", null: false
    t.datetime "updated_at", null: false
    t.index ["received_at"], name: "index_webhooks_on_received_at"
  end

  add_foreign_key "deliveries", "targets"
  add_foreign_key "deliveries", "webhooks"
  add_foreign_key "filters", "targets"
end
