require 'spec_helper'
require 'rack/mock'
require 'timeout'

# end-to-end: goes through config.ru exactly like rackup does
RSpec.describe 'POST /bulk_payments', type: :request do
  let(:app) { Rack::Builder.parse_file('config.ru') }
  let(:client) { Rack::MockRequest.new(app) }

  let(:payer_uuid) { '3f1c9a2e-7b4d-4c1e-9a55-2d8e6f0b7c41' } # Pinecrest CPA Group, 5_000_000
  let(:lopez_uuid) { '8b2e4c71-0d3a-4f6e-b1c9-5a7d2e9f4c10' } # Lopez Bookkeeping, 50_000
  let(:nair_uuid)  { 'e5f18b3c-2a9d-4c07-8e6b-1d4a7f9c3b25' } # Nair Tax Services, 200_000
  let(:unknown_uuid) { 'aa819b12-f953-40ed-b4fe-68b30729cc6e' }

  let(:initial_total) { 5_000_000 + 50_000 + 200_000 }
  let(:payload_1_total) { 625_000 + 580_050 + 120_075 }

  let(:payload) { fixture('payload_1.json') }

  before { seed_data }

  def fixture(name) = JSON.parse(File.read("./spec/fixtures/#{name}"))

  # a request blocked on a row lock would otherwise hang the suite instead of failing it
  def post(body, path: '/bulk_payments')
    Timeout.timeout(10) { client.post(path, input: body.is_a?(String) ? body : body.to_json) }
  end

  def balance(uuid) = Firm.find_by!(uuid:).balance_cents

  def balances = Firm.order(:id).pluck(:uuid, :balance_cents).to_h

  def set_balance(uuid, cents) = Firm.find_by!(uuid:).update!(balance_cents: cents)

  # every rejected request must leave the ledger untouched
  shared_examples 'no side effects' do
    it 'does not change any balance or create payments' do
      before_balances = balances
      response
      expect(balances).to eq(before_balances)
      expect(Payment.count).to eq(0)
    end
  end

  describe 'routing' do
    it 'rejects other paths with 404' do
      expect(post(payload, path: '/').status).to eq(404)
      expect(post(payload, path: '/bulk_payments/extra').status).to eq(404)
    end

    it 'no longer serves the old /bulk_get path' do
      expect(post(payload, path: '/bulk_get').status).to eq(404)
    end

    it 'rejects non-POST methods with 405' do
      expect(client.get('/bulk_payments').status).to eq(405)
      expect(client.put('/bulk_payments', input: payload.to_json).status).to eq(405)
      expect(client.delete('/bulk_payments').status).to eq(405)
    end
  end

  describe '201 Created' do
    subject(:response) { post(payload) }

    it 'responds with 201' do
      expect(response.status).to eq(201)
      expect(response.body).to eq('Created')
    end

    it 'debits the payer by the total of all payments' do
      response
      expect(balance(payer_uuid)).to eq(5_000_000 - payload_1_total)
    end

    it 'credits each payee with the sum of its payments' do
      response
      expect(balance(nair_uuid)).to eq(200_000 + 625_000 + 580_050)
      expect(balance(lopez_uuid)).to eq(50_000 + 120_075)
    end

    it 'conserves the total amount of money' do
      response
      expect(Firm.sum(:balance_cents)).to eq(initial_total)
    end

    it 'records one payment per requested payment' do
      response
      payer = Firm.find_by!(uuid: payer_uuid)

      rows = Payment.order(:id).map { |p| [p.payer_firm_id, p.payee_firm.uuid, p.amount_cents, p.description] }
      expect(rows).to eq([
        [payer.id, nair_uuid, 625_000, 'Overflow returns, August 2026'],
        [payer.id, nair_uuid, 580_050, 'Amended returns, August 2026'],
        [payer.id, lopez_uuid, 120_075, 'Bookkeeping cleanup, 3 clients']
      ])
      expect(Payment.where(created_at: nil)).to be_empty
    end

    context 'when payer balance exactly equals the total' do
      before { set_balance(payer_uuid, payload_1_total) }

      it 'accepts the request and leaves the payer at zero' do
        expect(response.status).to eq(201)
        expect(balance(payer_uuid)).to eq(0)
        expect(Payment.count).to eq(3)
      end
    end

    context 'when a payee starts with zero balance' do
      before { set_balance(lopez_uuid, 0) }

      it 'accepts payments to that firm' do
        expect(response.status).to eq(201)
        expect(balance(lopez_uuid)).to eq(120_075)
      end
    end
  end

  describe '422 Unprocessable Entity' do
    subject(:response) { post(payload) }

    context 'when payer cannot cover the total' do
      let(:payload) { fixture('payload_not_enough_balance.json') }

      it 'denies the whole request' do
        expect(response.status).to eq(422)
        expect(response.body).to eq('Insufficient balance')
      end

      include_examples 'no side effects'
    end

    context 'when payer is one cent short' do
      before { set_balance(payer_uuid, payload_1_total - 1) }

      it 'denies the whole request' do
        expect(response.status).to eq(422)
      end

      include_examples 'no side effects'
    end

    context 'when payer could cover some payments but not all' do
      before { set_balance(payer_uuid, 625_000) } # enough for the first payment only

      it 'does not pay anyone' do
        expect(response.status).to eq(422)
      end

      include_examples 'no side effects'
    end

    it 'denies once earlier requests have drained the balance' do
      statuses = 4.times.map { post(payload).status }

      expect(statuses).to eq([201, 201, 201, 422])
      expect(balance(payer_uuid)).to eq(5_000_000 - payload_1_total * 3)
      expect(Payment.count).to eq(9)
    end
  end

  describe '400 Bad Request' do
    subject(:response) { post(body) }

    invalid_bodies = {
      'unparseable JSON'          => ->(_) { '{"payer_firm_uuid": ' },
      'empty body'                => ->(_) { '' },
      'top-level array'           => ->(_) { '[]' },
      'top-level string'          => ->(_) { '"hello"' },
      'missing payer uuid'        => ->(p) { p.except('payer_firm_uuid') },
      'malformed payer uuid'      => ->(p) { p.merge('payer_firm_uuid' => 'dummy') },
      'non-string payer uuid'     => ->(p) { p.merge('payer_firm_uuid' => 42) },
      'missing payments'          => ->(p) { p.except('payments') },
      'payments not a list'       => ->(p) { p.merge('payments' => { 'amount' => '1' }) },
      'empty payments'            => ->(p) { p.merge('payments' => []) },
      'payment not an object'     => ->(p) { p.merge('payments' => ['6250']) },
      'missing amount'            => ->(p) { p.tap { p['payments'][0].delete('amount') } },
      'numeric amount'            => ->(p) { p.tap { p['payments'][0]['amount'] = 6250 } },
      'garbage amount'            => ->(p) { p.tap { p['payments'][0]['amount'] = '12abc' } },
      'negative amount'           => ->(p) { p.tap { p['payments'][0]['amount'] = '-5' } },
      'zero amount'               => ->(p) { p.tap { p['payments'][0]['amount'] = '0.00' } },
      'more than 2 decimals'      => ->(p) { p.tap { p['payments'][0]['amount'] = '1.005' } },
      'missing payee uuid'        => ->(p) { p.tap { p['payments'][0].delete('payee_firm_uuid') } },
      'malformed payee uuid'      => ->(p) { p.tap { p['payments'][0]['payee_firm_uuid'] = 'dummy' } },
      'payer paying itself'       => ->(p) { p.tap { p['payments'][0]['payee_firm_uuid'] = p['payer_firm_uuid'] } },
      'payer paying itself (uppercase)' => ->(p) { p.tap { p['payments'][0]['payee_firm_uuid'] = p['payer_firm_uuid'].upcase } },
      'missing description'       => ->(p) { p.tap { p['payments'][0].delete('description') } }
    }

    invalid_bodies.each do |name, mutate|
      context "with #{name}" do
        let(:body) { mutate.call(payload) }

        it 'responds with 400' do
          expect(response.status).to eq(400)
          expect(response.body).to start_with('Invalid JSON submitted')
        end

        include_examples 'no side effects'
      end
    end

    # proves validation runs before any money moves
    context 'when only the last payment is invalid' do
      let(:body) { payload.tap { |p| p['payments'][-1]['amount'] = 'oops' } }

      it 'responds with 400' do
        expect(response.status).to eq(400)
      end

      include_examples 'no side effects'
    end
  end

  describe '404 Not Found' do
    subject(:response) { post(body) }

    context 'when a payee does not exist' do
      let(:body) { fixture('payload_non_existent_firm.json') }

      it 'responds with 404 naming the firm' do
        expect(response.status).to eq(404)
        expect(response.body).to include('e9f99b9c-2a9d-4c07-8e6b-1d4a7f9c3b25')
      end

      include_examples 'no side effects'
    end

    context 'when the payer does not exist' do
      let(:body) { payload.merge('payer_firm_uuid' => unknown_uuid) }

      it 'responds with 404 naming the firm' do
        expect(response.status).to eq(404)
        expect(response.body).to include(unknown_uuid)
      end

      include_examples 'no side effects'
    end
  end

  describe '503 Service Unavailable' do
    # holds a row lock from another connection, like a concurrent request on another instance would
    def hold_lock_on(uuid)
      locked = Queue.new
      release = Queue.new
      thread = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Firm.transaction do
            Firm.lock.find_by!(uuid:)
            locked << true
            release.pop
          end
        end
      end
      locked.pop
      [thread, release]
    end

    before { allow_any_instance_of(ProcessPayments).to receive(:puts) }

    context 'when a firm stays locked through all retries' do
      it 'gives up after 3 retries with 503 and changes nothing' do
        holder, release = hold_lock_on(payer_uuid)
        expect_any_instance_of(ProcessPayments).to receive(:sleep).exactly(3).times

        before_balances = balances
        response = post(payload)

        expect(response.status).to eq(503)
        expect(response.body).to include('try again')
        expect(balances).to eq(before_balances)
        expect(Payment.count).to eq(0)
      ensure
        release << true
        holder.join
      end
    end

    context 'when the lock is released between retries' do
      it 'succeeds on retry with 201' do
        holder, release = hold_lock_on(payer_uuid)
        allow_any_instance_of(ProcessPayments).to receive(:sleep) do
          release << true
          holder.join
        end

        response = post(payload)

        expect(response.status).to eq(201)
        expect(balance(payer_uuid)).to eq(5_000_000 - payload_1_total)
        expect(Payment.count).to eq(3)
      ensure
        release << true
        holder.join
      end
    end
  end

  describe '500 Internal Server Error' do
    it 'rolls back everything when processing fails midway' do
      calls = 0
      allow(Payment).to receive(:create!).and_wrap_original do |original, *args, **kwargs|
        calls += 1
        raise 'boom' if calls == 2
        original.call(*args, **kwargs)
      end

      before_balances = balances
      response = post(payload)

      expect(response.status).to eq(500)
      expect(response.body).to eq('Service error')
      expect(response.body).not_to include('boom')
      expect(balances).to eq(before_balances)
      expect(Payment.count).to eq(0)
    end
  end

  describe 'concurrent requests' do
    # the main thread holds one connection, keep the rest of the default pool (5) for workers
    let(:thread_count) { 4 }

    before do
      allow_any_instance_of(ProcessPayments).to receive(:puts)
      allow_any_instance_of(ProcessPayments).to receive(:sleep) { Kernel.sleep(rand * 0.05) }
    end

    def post_concurrently(payloads)
      payloads.map { |p| Thread.new { post(p).status } }.map(&:value)
    end

    it 'never overdraws the payer' do
      set_balance(payer_uuid, payload_1_total * 2) # enough for exactly 2 requests
      total_before = Firm.sum(:balance_cents)

      statuses = post_concurrently(Array.new(thread_count) { fixture('payload_1.json') })
      succeeded = statuses.count(201)

      expect(statuses - [201, 422, 503]).to be_empty
      expect(succeeded).to be_between(1, 2)
      expect(succeeded).to eq(2) if statuses.include?(422) # 422 only once the balance is actually spent
      expect(balance(payer_uuid)).to eq(payload_1_total * (2 - succeeded))
      expect(Payment.count).to eq(3 * succeeded)
      expect(Firm.sum(:balance_cents)).to eq(total_before)
    end

    it 'does not deadlock or lose money when firms pay each other' do
      a_to_b = { 'payer_firm_uuid' => payer_uuid,
                 'payments' => [{ 'amount' => '100', 'payee_firm_uuid' => lopez_uuid, 'description' => 'a->b' }] }
      b_to_a = { 'payer_firm_uuid' => lopez_uuid,
                 'payments' => [{ 'amount' => '100', 'payee_firm_uuid' => payer_uuid, 'description' => 'b->a' }] }

      statuses = post_concurrently(Array.new(thread_count) { |i| i.even? ? a_to_b : b_to_a })

      expect(statuses - [201, 503]).to be_empty
      expect(Firm.sum(:balance_cents)).to eq(initial_total)
      expect(Payment.count).to eq(statuses.count(201))
    end
  end
end
