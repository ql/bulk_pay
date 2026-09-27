class CreatePayments < ActiveRecord::Migration[8.1]
  def change
    create_table "payments" do |t|
      t.references :payer_firm, foreign_key: { to_table: :firms }
      t.references :payee_firm, foreign_key: { to_table: :firms }
      t.integer :amount_cents, null: false
      t.text :description
      t.check_constraint "amount_cents > 0", name: "positive_amount"
      t.check_constraint "payee_firm_id <> payer_firm_id", name: "no_self_payments"
    end
  end
end
