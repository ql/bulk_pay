# this might be split into 1) validator 2) payment processor 3) transaction handler or smth
# however it's not yet viable while it contains only 100 lines - better to keep all in one place for now
class ProcessPayments
  AMOUNT_FORMAT = /\A(\d+)(?:\.(\d{1,2}))?\z/

  attr_accessor :json

  def initialize(json) = @json = json

  def call
    validate_and_prepare
    uuids = extract_firm_uids
    ActiveRecord::Base.transaction(isolation: :read_committed) do
      atomic_lock_and_cache_firms(uuids)
      return false unless sufficient_payer_balance?

      json['payments'].each { |p| process_payment(p) }
    end

    true
  rescue ActiveRecord::SerializationFailure, ActiveRecord::LockWaitTimeout => e
    @retries ||= 0
    if @retries < 3
      @retries += 1
      delay = rand * @retries
      puts "Thread #{Thread.current.object_id} got #{e.class} failure, retrying in #{delay} s. (retry ##{@retries})"
      sleep(delay)
      retry
    else
      raise(App::ConcurrencyError, "unable to fullfill request, try again")
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
      payer_firm:,
      payee_firm:,
      amount_cents: amount,
      description: payment['description']
    )
  end

  # poor man's schema checker here
  def validate_and_prepare
    raise App::InvalidInputJson, 'missing field "payer_firm_uuid"' unless payer_uuid
    raise App::InvalidInputJson, 'missing field "payments"' unless json['payments'].is_a?(Array)

    json['payments'].each do |p|
      raise App::InvalidInputJson, 'missing field "amount"' unless p['amount']
      raise App::InvalidInputJson, 'missing field "payee_firm_uuid"' unless p['payee_firm_uuid']
      raise App::InvalidInputJson, 'same field "payee_firm_uuid"' if p['payee_firm_uuid'] == payer_uuid
      raise App::InvalidInputJson, 'missing field "description"' unless p['description']
    end

    true
  end

  def sufficient_payer_balance? = cached_firm(payer_uuid).balance_cents >= json['payments'].map { |p| parse_amount(p['amount']) }.sum

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
  # accepts only strings like "300", "5.5", "9.99" - floats are ambiguous for money
  def parse_amount(dollars_amount)
    match = AMOUNT_FORMAT.match(dollars_amount) if dollars_amount.is_a?(String)
    raise App::InvalidInputJson, "wrong amount format #{dollars_amount}" unless match

    dollars, cents = match.captures
    amount = dollars.to_i * 100 + cents.to_s.ljust(2, '0').to_i
    raise App::InvalidInputJson, "wrong amount format #{dollars_amount}" unless amount.positive?

    amount
  end
end
