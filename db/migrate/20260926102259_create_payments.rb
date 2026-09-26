class CreatePayments < ActiveRecord::Migration[8.1]
  def change
    create_table "payments" do |t|
      t.references :payer_firm, null: false, foreign_key: { to_table: :firms }
      t.references :payee_firm, null: false, foreign_key: { to_table: :firms }
      t.integer :amount_cents
      t.text :description
      t.timestamps
    end
  end
end
