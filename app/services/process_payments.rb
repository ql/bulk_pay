# this might be split into 1) validator 2) payment processor 3) transaction handler or smth
# however it's not yet viable while it contains only 100 lines - better to keep all in one place for now
class ProcessPayments
  AMOUNT_FORMAT = /\A(\d+)(?:\.(\d{1,2}))?\z/
  UUID_FORMAT = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/
  MAX_PAYMENTS = 1000 # bounds lock hold time and insert statement size
  LOCK_TIMEOUT = ENV.fetch('LOCK_TIMEOUT', '3s') # applies to each row lock separately
  STATEMENT_TIMEOUT = ENV.fetch('STATEMENT_TIMEOUT', '5s') # caps total wait for all row locks

  attr_reader :json, :amounts

  def initialize(json) = @json = json

  def call
    validate_and_prepare

    ActiveRecord::Base.transaction(isolation: :read_committed) do
      set_local_timeouts
      firms = lock_firms
      next false if firms[payer_uuid].balance_cents < amounts.sum

      apply_balance_deltas(firms)
      insert_payments(firms)
      true
    end
  rescue ActiveRecord::LockWaitTimeout, ActiveRecord::QueryCanceled, ActiveRecord::Deadlocked
    raise App::ConcurrencyError, 'unable to fulfill request, try again'
  end

  private

  def set_local_timeouts
    ActiveRecord::Base.with_connection do |connection|
      connection.execute("SET LOCAL lock_timeout = #{connection.quote(LOCK_TIMEOUT)}")
      connection.execute("SET LOCAL statement_timeout = #{connection.quote(STATEMENT_TIMEOUT)}")
    end
  end

  # this is the most important piece of whole concurrency thing:
  # locking in id order means concurrent requests never deadlock each other, they just wait
  def lock_firms
    uuids = [payer_uuid] + json['payments'].map { |p| p['payee_firm_uuid'] }.uniq
    firms = Firm.where(uuid: uuids).order(:id).lock.index_by(&:uuid)

    missing = uuids - firms.keys
    raise ActiveRecord::RecordNotFound, "firm #{missing.first} not found" if missing.any?

    firms
  end

  # rows are locked, so writing absolute values can't lose a concurrent update
  def apply_balance_deltas(firms)
    deltas = Hash.new(0)
    json['payments'].zip(amounts) { |p, amount| deltas[p['payee_firm_uuid']] += amount }
    deltas[payer_uuid] -= amounts.sum

    deltas.each do |uuid, delta|
      firm = firms.fetch(uuid)
      firm.balance_cents += delta
      firm.save!
    end
  end

  def insert_payments(firms)
    payer_id = firms.fetch(payer_uuid).id
    rows = json['payments'].zip(amounts).map do |p, amount|
      {
        payer_firm_id: payer_id,
        payee_firm_id: firms.fetch(p['payee_firm_uuid']).id,
        amount_cents: amount,
        description: p['description']
      }
    end

    Payment.insert_all!(rows)
  end

  # poor man's schema checker here
  def validate_and_prepare
    raise App::InvalidInputJson, 'request body must be a JSON object' unless json.is_a?(Hash)
    raise App::InvalidInputJson, 'missing field "payer_firm_uuid"' unless payer_uuid
    raise App::InvalidInputJson, 'invalid field "payer_firm_uuid"' unless uuid?(payer_uuid)
    raise App::InvalidInputJson, 'missing field "payments"' unless json['payments'].is_a?(Array)
    raise App::InvalidInputJson, 'empty field "payments"' if json['payments'].empty?
    raise App::InvalidInputJson, "too many payments, max #{MAX_PAYMENTS}" if json['payments'].size > MAX_PAYMENTS

    json['payer_firm_uuid'] = payer_uuid.downcase

    json['payments'].each do |p|
      raise App::InvalidInputJson, 'payment must be a JSON object' unless p.is_a?(Hash)
      raise App::InvalidInputJson, 'missing field "amount"' unless p['amount']
      raise App::InvalidInputJson, 'missing field "payee_firm_uuid"' unless p['payee_firm_uuid']
      raise App::InvalidInputJson, 'invalid field "payee_firm_uuid"' unless uuid?(p['payee_firm_uuid'])

      p['payee_firm_uuid'] = p['payee_firm_uuid'].downcase
      raise App::InvalidInputJson, 'same field "payee_firm_uuid"' if p['payee_firm_uuid'] == payer_uuid
      raise App::InvalidInputJson, 'missing field "description"' unless p['description']
    end

    @amounts = json['payments'].map { |p| parse_amount(p['amount']) }

    true
  end

  def payer_uuid = json['payer_firm_uuid']

  def uuid?(value) = value.is_a?(String) && UUID_FORMAT.match?(value)

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
