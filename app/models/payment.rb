class Payment < ActiveRecord::Base
  validates :payer_firm_id, :payee_firm_id, :amount_cents, presence: true
  validates :amount_cents, presence: true, comparison: { greater_than: 0 }
  validates :payer_firm_id, comparison: { other_than: :payee_firm_id }

  belongs_to :payer_firm, class_name: 'Firm', foreign_key: :payer_firm_id, primary_key: :uuid
  belongs_to :payee_firm, class_name: 'Firm', foreign_key: :payee_firm_id, primary_key: :uuid
end
