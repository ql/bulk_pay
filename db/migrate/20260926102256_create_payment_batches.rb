class CreatePaymentBatches < ActiveRecord::Migration[8.1]
  def change
    create_table "payment_batches" do |t|
      t.references :payer_firm, null: false, foreign_key: { to_table: :firms }, index: false
      t.string :idempotency_key, null: false, limit: 255
      t.string :request_hash, null: false, limit: 64
      t.timestamps
      t.index [:payer_firm_id, :idempotency_key], unique: true
    end
  end
end
