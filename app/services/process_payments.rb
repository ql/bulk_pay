class ProcessPayments
  attr_accessor :json

  def initialize(json)
    @json = json
  end

  def call
    validate_and_prepare
    return false unless sufficient_payer_balance?

    json['payments'].each do |p|
      process_payment(p)
    end

    true
  end

  private

  def process_payment(payment)
    payee_firm = find_firm!(payment['payee_firm_uuid'])

    amount = payment['amount']
    payee_firm.transaction do
      payee_firm.balance_cents += amount
      payer_firm.balance_cents -= amount
      payee_firm.save!
      payer_firm.save!
      Payment.create!(
        payer_firm_id: payer_firm.uuid,
        payee_firm_id: payee_firm.uuid,
        amount_cents: amount,
        description: payment['description']
      )
    end
  end

  # poor man's schema checker here
  def validate_and_prepare
    raise InvalidInputJson, 'missing field "payer_firm_uuid"' unless json['payer_firm_uuid']
    raise InvalidInputJson, 'missing field "payments"' unless json['payments'].is_a?(Array)

    json['payments'].each do |p|
      p['amount'] = parse_amount(p['amount'])
      raise InvalidInputJson, 'invalid field "amount"' unless p['amount'].positive?
      raise InvalidInputJson, 'missing field "payee_firm_uuid"' unless p['payee_firm_uuid']
      raise InvalidInputJson, 'missing field "description"' unless p['description']
    end

    true
  end

  def sufficient_payer_balance?
    payer_firm.balance_cents > json['payments'].map { |p| p['amount'] }.sum
  end

  def payer_firm
    @payer_firm ||= find_firm!(json['payer_firm_uuid'])
  end

  def find_firm!(uuid)
    firm = Firm.find_by(uuid:)
    # custom message for original exception for direct API use
    raise ActiveRecord::RecordNotFound, "firm #{uuid} not found" unless firm
    firm
  end

  # not using Money gem or such to keep surface small
  def parse_amount(dollars_amount)
    dollars, cents = dollars_amount.split('.')
    dollars = dollars.to_i
    raise ArgumentError, "wrong amount format" unless dollars.positive?

    if cents.present? && cents.to_i.zero?
      raise ArgumentError, "wrong amount format"
    end

    case cents.to_s.size
    when 0 # 300
      dollars * 100
    when 1 # 5.5
      dollars * 100 + cents.to_i * 10
    when 2 # 9.99
      dollars * 100 + cents.to_i
    else
      raise ArgumentError, "wrong amount format" if cents.size > 2
    end
  end
end
