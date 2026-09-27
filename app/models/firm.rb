class Firm < ActiveRecord::Base
  validates :name, :uuid, :balance_cents, presence: true
  validates :balance_cents, comparison: { greater_than: 0 }
  validates :uuid, uniqueness: true

  has_many :sent_payments, class_name: 'Payment', foreign_key: :payer_firm_id, primary_key: :uuid
  has_many :received_payments, class_name: 'Payment', foreign_key: :payee_firm_id, primary_key: :uuid
end
