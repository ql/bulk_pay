class CreatePayments < ActiveRecord::Migration[8.1]
  def change
    create_table "payments" do |t|
      t.references :payer_firm, type: :uuid, foreign_key: { to_table: :firms, primary_key: :uuid}
      t.references :payee_firm, type: :uuid, foreign_key: { to_table: :firms, primary_key: :uuid}
      t.integer :amount_cents, null: false
      t.text :description
      t.check_constraint "amount_cents > 0", name: "positive_amount"
      t.check_constraint "payee_firm_id <> payer_firm_id", name: "no_self_payments"
    end
  end
end
