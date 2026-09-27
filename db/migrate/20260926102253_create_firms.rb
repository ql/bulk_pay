class CreateFirms < ActiveRecord::Migration[8.1]
  def change
    create_table "firms" do |t|
      t.string :name, null: false
      t.integer :balance_cents, null: false
      t.uuid :uuid, null: false
      t.check_constraint "balance_cents >= 0", name: "non_negative_balance"
      t.index :uuid, unique: true
    end
  end
end
