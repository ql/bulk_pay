class Firm < ActiveRecord::Base
  validates :name, :uuid, :balance_cents, presence: true
  validates :balance_cents, comparison: { greater_than_or_equal_to: 0 }
  validates :uuid, uniqueness: true

  has_many :sent_payments, class_name: 'Payment', foreign_key: :payer_firm_id
  has_many :received_payments, class_name: 'Payment', foreign_key: :payee_firm_id
  has_many :payment_batches, foreign_key: :payer_firm_id
end
