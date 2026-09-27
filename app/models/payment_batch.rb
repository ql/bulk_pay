class PaymentBatch < ActiveRecord::Base
  validates :payer_firm_id, :idempotency_key, :request_hash, presence: true

  belongs_to :payer_firm, class_name: 'Firm'
  has_many :payments
end
