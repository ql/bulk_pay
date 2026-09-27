class Firm < ActiveRecord::Base
  validates :name, :uuid, :balance_cents, presence: true
  validates :balance_cents, comparison: { greater_than: 0 }
  validates :uuid, uniqueness: true

  has_many :sent_payments, class_name: 'Payment'
  has_many :received_payments, class_name: 'Payment'
end
