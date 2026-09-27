class ProcessPayments
  # charging phase: moves money for a valid request in a single transaction
  class Charge
    LOCK_TIMEOUT = ENV.fetch('LOCK_TIMEOUT', '3s') # applies to each row lock separately
    STATEMENT_TIMEOUT = ENV.fetch('STATEMENT_TIMEOUT', '5s') # caps total wait for all row locks

    attr_reader :request

    def initialize(request)
      raise ArgumentError, 'request must be validated before charging' unless request.validated?

      @request = request
    end

    def call
      ActiveRecord::Base.transaction(isolation: :read_committed) do
        set_local_timeouts
        firms = lock_firms
        # all requests of a payer serialize on its row lock, so no duplicate can commit between lookup and insert
        previous = previous_batch(firms)
        if previous
          raise App::IdempotencyKeyReused, 'Idempotency-Key was already used for a different request' unless previous.request_hash == request.fingerprint
          next :replayed
        end

        next :insufficient_balance if firms[request.payer_uuid].balance_cents < request.total_cents

        payment_batch = record_batch(firms)
        apply_balance_deltas(firms)
        insert_payments(firms, payment_batch)
        :created
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
      uuids = request.firm_uuids
      firms = Firm.where(uuid: uuids).order(:id).lock.index_by(&:uuid)

      missing = uuids - firms.keys
      raise ActiveRecord::RecordNotFound, "firm #{missing.first} not found" if missing.any?

      firms
    end

    def payer_id(firms) = firms.fetch(request.payer_uuid).id

    def previous_batch(firms) = PaymentBatch.find_by(payer_firm_id: payer_id(firms), idempotency_key: request.idempotency_key)

    def record_batch(firms)
      PaymentBatch.create!(payer_firm_id: payer_id(firms), idempotency_key: request.idempotency_key, request_hash: request.fingerprint)
    end

    # rows are locked, so writing absolute values can't lose a concurrent update
    def apply_balance_deltas(firms)
      deltas = Hash.new(0)
      request.payments.each { |p| deltas[p.payee_uuid] += p.amount_cents }
      deltas[request.payer_uuid] -= request.total_cents

      deltas.each do |uuid, delta|
        firm = firms.fetch(uuid)
        firm.balance_cents += delta
        firm.save!
      end
    end

    def insert_payments(firms, payment_batch)
      rows = request.payments.map do |p|
        {
          payment_batch_id: payment_batch.id,
          payer_firm_id: payer_id(firms),
          payee_firm_id: firms.fetch(p.payee_uuid).id,
          amount_cents: p.amount_cents,
          description: p.description
        }
      end

      Payment.insert_all!(rows)
    end
  end
end
