class ProcessPayments
  attr_accessor :json

  def initialize(json) = @json = json

  def call
    retries = 0
    validate_and_prepare
    uuids = extract_firm_uids
    ActiveRecord::Base.transaction(isolation: :read_committed) do
      atomic_lock_and_cache_firms(uuids)
      return false unless sufficient_payer_balance?

      json['payments'].each { |p| process_payment(p) }
    end

    true
  rescue ActiveRecord::SerializationFailure, ActiveRecord::LockWaitTimeout => e
    retries ||= 0
    if retries < 3
      retries += 1
      delay = rand * retries
      puts "Thread #{Thread.current.object_id} got #{e.class} failure, retrying in #{delay} s. (retry ##{retries})"
      sleep(delay)
      retry
    else
      raise(ConcurrencyError, "unable to fullfill request, try again")
    end
  end

  private

  def process_payment(payment)
    payer_firm = cached_firm(payer_uuid)
    payee_firm = cached_firm(payment['payee_firm_uuid'])

    amount = parse_amount(payment['amount'])

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

  # poor man's schema checker here
  def validate_and_prepare
    raise InvalidInputJson, 'missing field "payer_firm_uuid"' unless payer_uuid
    raise InvalidInputJson, 'missing field "payments"' unless json['payments'].is_a?(Array)

    json['payments'].each do |p|
      raise InvalidInputJson, 'missing field "amount"' unless p['amount']
      raise InvalidInputJson, 'missing field "payee_firm_uuid"' unless p['payee_firm_uuid']
      raise InvalidInputJson, 'same field "payee_firm_uuid"' if p['payee_firm_uuid'] == payer_uuid
      raise InvalidInputJson, 'missing field "description"' unless p['description']
    end

    true
  end

  def sufficient_payer_balance? = cached_firm(payer_uuid).balance_cents > json['payments'].map { |p| parse_amount(p['amount']) }.sum

  def payer_uuid = json['payer_firm_uuid']

  def extract_firm_uids = [payer_uuid] + json['payments'].map { |p| p['payee_firm_uuid'] }.uniq

  # this is the most important piece of whole concurrency thing
  def atomic_lock_and_cache_firms(uuids)
    @firm_cache = {}
    Firm.where(uuid: uuids).lock('FOR UPDATE NOWAIT').all.each do |f|
      @firm_cache[f.uuid] = f
    end
  end

  def cached_firm(uuid) = @firm_cache[uuid] || raise(ActiveRecord::RecordNotFound.new("firm #{uuid} not found"))

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
      raise ArgumentError, "wrong amount format"
    end
  end
end
