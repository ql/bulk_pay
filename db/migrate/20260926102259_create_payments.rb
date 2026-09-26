class CreatePayments < ActiveRecord::Migration[8.1]
  def change
    create_table "payments" do |t|
      t.uuid :payer_firm_id, null: false
      t.uuid :payee_firm_id, null: false
      t.integer :amount_cents
      t.text :description
    end
  end
end
