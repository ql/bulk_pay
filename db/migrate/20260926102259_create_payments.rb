class CreatePayments < ActiveRecord::Migration[8.1]
  def change
    create_table "payments" do |t|
      t.references :payer_firm, null: false, foreign_key: { to_table: :firms }
      t.references :payee_firm, null: false, foreign_key: { to_table: :firms }
      t.references :payment_batch, null: false, foreign_key: true
      t.bigint :amount_cents, null: false
      t.text :description, null: false
      t.timestamps
      t.check_constraint "amount_cents > 0", name: "positive_amount"
      t.check_constraint "payee_firm_id <> payer_firm_id", name: "no_self_payments"
    end
  end
end
