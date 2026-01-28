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

ActiveRecord::Schema[8.1].define(version: 2026_01_28_101750) do
  create_table "deliveries", force: :cascade do |t|
    t.integer "attempts", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "dispatched_at"
    t.string "error_message"
    t.datetime "last_retry_at"
    t.datetime "next_retry_at"
    t.text "response_body"
    t.integer "retry_stage", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.integer "status_code"
    t.integer "target_id", null: false
    t.datetime "updated_at", null: false
    t.integer "webhook_id", null: false
    t.index ["created_at"], name: "index_deliveries_on_created_at"
    t.index ["status", "next_retry_at"], name: "index_deliveries_on_failed_with_retry", where: "status = 2 AND next_retry_at IS NOT NULL"
    t.index ["status"], name: "index_deliveries_on_status"
    t.index ["target_id"], name: "index_deliveries_on_target_id"
    t.index ["webhook_id", "target_id"], name: "index_deliveries_on_webhook_id_and_target_id"
    t.index ["webhook_id"], name: "index_deliveries_on_webhook_id"
  end

  create_table "error_records", force: :cascade do |t|
    t.text "backtrace"
    t.json "context", default: {}, null: false
    t.datetime "created_at", null: false
    t.string "error_class", null: false
    t.string "fingerprint", null: false
    t.datetime "first_occurred_at", null: false
    t.datetime "last_occurred_at", null: false
    t.text "message"
    t.integer "occurrences_count", default: 1, null: false
    t.datetime "resolved_at"
    t.datetime "updated_at", null: false
    t.index ["fingerprint"], name: "index_error_records_on_fingerprint", unique: true
    t.index ["last_occurred_at"], name: "index_error_records_on_last_occurred_at"
    t.index ["resolved_at", "last_occurred_at"], name: "index_error_records_on_resolved_at_and_last_occurred_at"
    t.index ["resolved_at"], name: "index_error_records_on_resolved_at"
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
