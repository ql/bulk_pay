class Payment < ActiveRecord::Base
  validates :payer_firm_id, :payee_firm_id, :amount_cents, presence: true
  validates :description, exclusion: { in: [nil], message: "can't be nil" }
  validates :amount_cents, presence: true, comparison: { greater_than: 0 }
  validates :payer_firm_id, comparison: { other_than: :payee_firm_id }

  belongs_to :payer_firm, class_name: 'Firm'
  belongs_to :payee_firm, class_name: 'Firm'
end
