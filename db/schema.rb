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

ActiveRecord::Schema[8.1].define(version: 2026_09_26_102259) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "firms", force: :cascade do |t|
    t.string "name", null: false
    t.integer "balance_cents", null: false
    t.uuid "uuid", null: false
    t.index ["uuid"], name: "index_firms_on_uuid", unique: true
    t.check_constraint "balance_cents > 0", name: "positive_balance"
  end

  create_table "payments", force: :cascade do |t|
    t.uuid "payer_firm_id"
    t.uuid "payee_firm_id"
    t.integer "amount_cents", null: false
    t.text "description"
    t.index ["payee_firm_id"], name: "index_payments_on_payee_firm_id"
    t.index ["payer_firm_id"], name: "index_payments_on_payer_firm_id"
    t.check_constraint "amount_cents > 0", name: "positive_amount"
    t.check_constraint "payee_firm_id <> payer_firm_id", name: "no_self_payments"
  end

  add_foreign_key "payments", "firms", column: "payee_firm_id", primary_key: "uuid"
  add_foreign_key "payments", "firms", column: "payer_firm_id", primary_key: "uuid"
end
