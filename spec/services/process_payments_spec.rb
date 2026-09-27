require 'spec_helper'

RSpec.describe ProcessPayments, type: :service do
  subject { described_class.new(payload).call }

  let(:base_payload) { JSON.parse(File.read('./spec/fixtures/payload_1.json')) }
  let(:payload) { base_payload }

  before(:each) { seed_data }

  describe "when JSON is invalid" do
    let(:payload) { {} }

    it "should raise an InvalidInputJson exception" do
      expect { subject }.to raise_exception(App::InvalidInputJson)
    end
  end

  describe "when payments list is empty" do
    let(:payload) { base_payload.merge('payments' => []) }

    it "should raise an InvalidInputJson exception" do
      expect { subject }.to raise_exception(App::InvalidInputJson, 'empty field "payments"')
    end
  end

  describe "when JSON top level is not an object" do
    let(:payload) { [] }

    it "should raise an InvalidInputJson exception" do
      expect { subject }.to raise_exception(App::InvalidInputJson, 'request body must be a JSON object')
    end
  end

  describe "when a payment is not an object" do
    let(:payload) { base_payload.merge('payments' => ['6250']) }

    it "should raise an InvalidInputJson exception" do
      expect { subject }.to raise_exception(App::InvalidInputJson, 'payment must be a JSON object')
    end
  end

  describe "when payer uuid is malformed" do
    let(:payload) { base_payload.merge('payer_firm_uuid' => 'dummy') }

    it "should raise an InvalidInputJson exception" do
      expect { subject }.to raise_exception(App::InvalidInputJson, 'invalid field "payer_firm_uuid"')
    end
  end

  describe "when payee uuid is malformed" do
    let(:payload) { base_payload.tap { |p| p['payments'][0]['payee_firm_uuid'] = 42 } }

    it "should raise an InvalidInputJson exception" do
      expect { subject }.to raise_exception(App::InvalidInputJson, 'invalid field "payee_firm_uuid"')
    end
  end

  describe "when uuids are uppercase" do
    let(:payload) do
      base_payload.tap do |p|
        p['payer_firm_uuid'] = p['payer_firm_uuid'].upcase
        p['payments'].each { |payment| payment['payee_firm_uuid'] = payment['payee_firm_uuid'].upcase }
      end
    end

    it "should match firms case-insensitively" do
      expect(subject).to be true
    end
  end

  describe "when payer pays itself using uppercase uuid" do
    let(:payload) { base_payload.tap { |p| p['payments'][0]['payee_firm_uuid'] = p['payer_firm_uuid'].upcase } }

    it "should raise an InvalidInputJson exception" do
      expect { subject }.to raise_exception(App::InvalidInputJson, 'same field "payee_firm_uuid"')
    end
  end

  describe "amounts" do
    subject { described_class.new(payload).send(:parse_amount, amount) }

    describe "with garbage input" do
      let(:amount) { "some gibberish" }
      it { expect { subject }.to raise_exception(App::InvalidInputJson, /wrong amount format/) }
    end

    describe "with mangled decimals" do
      let(:amount) { "100.gibberish" }
      it { expect { subject }.to raise_exception(App::InvalidInputJson, /wrong amount format/) }
    end

    describe "with too much decimals" do
      let(:amount) { "100.3234234" }
      it { expect { subject }.to raise_exception(App::InvalidInputJson, /wrong amount format/) }
    end

    describe "with trailing garbage" do
      let(:amount) { "1.5x" }
      it { expect { subject }.to raise_exception(App::InvalidInputJson, /wrong amount format/) }
    end

    describe "with leading number followed by garbage" do
      let(:amount) { "12abc" }
      it { expect { subject }.to raise_exception(App::InvalidInputJson, /wrong amount format/) }
    end

    describe "with several dots" do
      let(:amount) { "1.2.3" }
      it { expect { subject }.to raise_exception(App::InvalidInputJson, /wrong amount format/) }
    end

    describe "with exponent notation" do
      let(:amount) { "1e3" }
      it { expect { subject }.to raise_exception(App::InvalidInputJson, /wrong amount format/) }
    end

    describe "with non-string amount" do
      let(:amount) { 6250 }
      it { expect { subject }.to raise_exception(App::InvalidInputJson, /wrong amount format/) }
    end

    describe "with zero amount" do
      let(:amount) { "0.00" }
      it { expect { subject }.to raise_exception(App::InvalidInputJson, /wrong amount format/) }
    end

    describe "with sub-dollar amount" do
      let(:amount) { "0.50" }
      it { expect(subject).to eq(50) }
    end

    describe "with zero cents" do
      let(:amount) { "10.00" }
      it { expect(subject).to eq(1000) }
    end

    describe "with single zero decimal" do
      let(:amount) { "10.0" }
      it { expect(subject).to eq(1000) }
    end

    describe "with leading zero in cents" do
      let(:amount) { "10.05" }
      it { expect(subject).to eq(1005) }
    end

    describe "without decimals" do
      let(:amount) { "300" }
      it { expect(subject).to eq(30000) }
    end

    describe "with tenth of cent" do
      let(:amount) { "50.5" }
      it { expect(subject).to eq(5050) }
    end

    describe "with cents" do
      let(:amount) { "9.99" }
      it { expect(subject).to eq(999) }
    end
  end

  describe "when any of firms is not found" do
    let(:payload) { base_payload.merge('payer_firm_uuid' => 'aa819b12-f953-40ed-b4fe-68b30729cc6e') }

    it "should raise a RecordNotFound exception" do
      expect { subject }.to raise_exception(ActiveRecord::RecordNotFound, "firm aa819b12-f953-40ed-b4fe-68b30729cc6e not found")
    end
  end

  describe "when there are no enough funds" do
    let(:payload) do
      n = base_payload
      n['payments'].each { |p| p['amount'] = '99999999' }
      n
    end

    it "should return false, so app responds with 422 Not Enough Funds" do
      expect(subject).to be false
    end
  end

  describe "when payer balance exactly equals the total" do
    before { Firm.find_by(name: 'Pinecrest CPA Group').update!(balance_cents: 625000 + 580050 + 120075) }

    it "should spend the whole balance down to zero" do
      expect(subject).to be true
      expect(Firm.find_by(name: 'Pinecrest CPA Group').balance_cents).to eq(0)
    end
  end

  describe "when there are enough funds" do
    it "should save whole batch in a ledger and return true" do
      expect(Firm.pluck(:balance_cents).sum).to eq(5000000 + 200000 + 50000)

      result = subject
      expect(result).to be true

      expect(Firm.pluck(:balance_cents).sum).to eq(5000000 + 200000 + 50000)
      expect(Firm.find_by(name: 'Pinecrest CPA Group').balance_cents).to eq(5000000 - 625000 - 580050 - 120075)
      expect(Firm.find_by(name: 'Lopez Bookkeeping').balance_cents).to eq(50000 + 120075)
      expect(Firm.find_by(name: 'Nair Tax Services').balance_cents).to eq(200000 + 625000 + 580050)

      expect(Payment.count).to eq(3)
      expect(Payment.where(created_at: nil)).to be_empty

      lopez_payment = Payment.find_by(amount_cents: 120075)
      expect(lopez_payment.description).to eq("Bookkeeping cleanup, 3 clients")
      expect(lopez_payment.payer_firm.uuid).to eq('3f1c9a2e-7b4d-4c1e-9a55-2d8e6f0b7c41')
      expect(lopez_payment.payee_firm.uuid).to eq('8b2e4c71-0d3a-4f6e-b1c9-5a7d2e9f4c10')
    end

    describe "with concurrent requests" do
      # this spec is intentionally left as a potentially flaky non-deterministic one - that's the price for catching failing invariants
      it "doesnt corrupt ledger state and mostly works hehe" do
        Firm.find_by(name: 'Pinecrest CPA Group').update(balance_cents: 1_000_000_000)
        expect(Firm.pluck(:balance_cents).sum).to eq(1_000_000_000 + 200000 + 50000)
        thread_number = 50

        threads = []
        results = []
        thread_number.times do |number|
          threads << Thread.new do
            result = described_class.new(payload).call
            results << result
            puts "Thread ##{number}(#{Thread.current.object_id}) - balances update: #{result}"
          end
        end
        threads.each(&:join)

        expect(Firm.pluck(:balance_cents).sum).to eq(1_000_000_000 + 200000 + 50000)
        expect(Firm.find_by(name: 'Pinecrest CPA Group').balance_cents).to eq(1_000_000_000 - (625000 + 580050 + 120075) * thread_number)
        expect(results.all?).to be true
      end

      # this one reproduces deadlocks quite good, not sure if getting rid of them is in scope
      it "doesnt suffer from deadlocks when payments are circular" do
        payload['payments'][0]['amount'] = '100' # a lot of small payments to each other
        payload['payments'][1]['amount'] = '100'
        payload['payments'][2]['amount'] = '100'

        payload2 = JSON.parse(File.read('./spec/fixtures/payload_1.json'))
        payload2['payer_firm_uuid'] = '8b2e4c71-0d3a-4f6e-b1c9-5a7d2e9f4c10'
        payload2['payments'][2]['payee_firm_uuid'] = '3f1c9a2e-7b4d-4c1e-9a55-2d8e6f0b7c41'
        payload2['payments'][0]['amount'] = '100' 
        payload2['payments'][1]['amount'] = '100'
        payload2['payments'][2]['amount'] = '100'

        payload3 = JSON.parse(File.read('./spec/fixtures/payload_1.json'))
        payload3['payer_firm_uuid'] = 'e5f18b3c-2a9d-4c07-8e6b-1d4a7f9c3b25'
        payload3['payments'][0]['payee_firm_uuid'] = '3f1c9a2e-7b4d-4c1e-9a55-2d8e6f0b7c41'
        payload3['payments'][0]['amount'] = '100'
        payload3['payments'][1]['payee_firm_uuid'] = '3f1c9a2e-7b4d-4c1e-9a55-2d8e6f0b7c41'
        payload3['payments'][1]['amount'] = '100'
        payload3['payments'][2]['amount'] = '100'

        Firm.update_all(balance_cents: 5000000)
        thread_number = 10

        threads = []
        results = []
        payloads = [payload, payload2, payload3]
        thread_number.times do |number|
          threads << Thread.new do
            result = described_class.new(payloads[number % 3]).call
            results << result
            puts "Thread ##{number}(#{Thread.current.object_id}) - balances update: #{result}"
          end
        end
        threads.each(&:join)

        expect(Firm.pluck(:balance_cents).sum).to eq(5000000 * 3)
        expect(results.all?).to be true
      end
    end

    describe "when system error occurs in the middle of processing" do
      it "should not leave partly modified rows" do
        modified_subject = described_class.new(payload)
        def modified_subject.cached_firm(uuid)
          raise RuntimeError, "oopsie!" if uuid == '8b2e4c71-0d3a-4f6e-b1c9-5a7d2e9f4c10'
          Firm.find_by(uuid:)
        end

        expect(Payment.count).to eq(0)
        expect(Firm.pluck(:balance_cents).sum).to eq(5000000 + 200000 + 50000)
        expect { modified_subject.call }.to raise_exception(RuntimeError, 'oopsie!')
        expect(Firm.pluck(:balance_cents).sum).to eq(5000000 + 200000 + 50000)
        expect(Payment.count).to eq(0)
        expect(Firm.find_by(name: 'Pinecrest CPA Group').balance_cents).to eq(5000000)
        expect(Firm.find_by(name: 'Lopez Bookkeeping').balance_cents).to eq(50000)
        expect(Firm.find_by(name: 'Nair Tax Services').balance_cents).to eq(200000)
      end
    end
  end
end
