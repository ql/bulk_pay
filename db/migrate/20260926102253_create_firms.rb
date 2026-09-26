class CreateFirms < ActiveRecord::Migration[8.1]
  def change
    create_table "firms" do |t|
      t.string :name, null: false
      t.integer :balance_cents
      t.uuid :uuid
      t.timestamps
    end
  end
end
