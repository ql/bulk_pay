require 'spec_helper'

RSpec.describe ProcessPayments::Request do
  subject { described_class.new(payload, idempotency_key:).validate! }

  let(:base_payload) { JSON.parse(File.read('./spec/fixtures/payload_1.json')) }
  let(:payload) { base_payload }
  let(:idempotency_key) { SecureRandom.uuid }

  it 'normalizes the request' do
    payload['payer_firm_uuid'] = payload['payer_firm_uuid'].upcase
    payload['payments'][2]['payee_firm_uuid'] = payload['payments'][2]['payee_firm_uuid'].upcase

    expect(subject.payer_uuid).to eq('3f1c9a2e-7b4d-4c1e-9a55-2d8e6f0b7c41')
    expect(subject.payments.map(&:to_h)).to eq([
      { payee_uuid: 'e5f18b3c-2a9d-4c07-8e6b-1d4a7f9c3b25', amount_cents: 625_000, description: 'Overflow returns, August 2026' },
      { payee_uuid: 'e5f18b3c-2a9d-4c07-8e6b-1d4a7f9c3b25', amount_cents: 580_050, description: 'Amended returns, August 2026' },
      { payee_uuid: '8b2e4c71-0d3a-4f6e-b1c9-5a7d2e9f4c10', amount_cents: 120_075, description: 'Bookkeeping cleanup, 3 clients' }
    ])
    expect(subject.total_cents).to eq(625_000 + 580_050 + 120_075)
    expect(subject.firm_uuids).to eq(%w[3f1c9a2e-7b4d-4c1e-9a55-2d8e6f0b7c41 e5f18b3c-2a9d-4c07-8e6b-1d4a7f9c3b25 8b2e4c71-0d3a-4f6e-b1c9-5a7d2e9f4c10])
    expect(subject).to be_frozen
  end

  it 'does not validate on construction' do
    request = described_class.new([], idempotency_key: nil)

    expect(request).not_to be_validated
    expect { request.validate! }.to raise_exception(App::InvalidInputJson)
    expect(request).not_to be_validated
  end

  it 'returns itself from validate! and validates only once' do
    request = described_class.new(payload, idempotency_key:)

    expect(request.validate!).to be(request)
    expect(request).to be_validated
    expect(request.validate!).to be(request)
  end

  it 'does not modify the given payload' do
    payload['payer_firm_uuid'] = payload['payer_firm_uuid'].upcase
    original = Marshal.load(Marshal.dump(payload))

    subject

    expect(payload).to eq(original)
  end

  describe 'fingerprint' do
    def fingerprint(json) = described_class.new(json, idempotency_key:).validate!.fingerprint

    it 'is the same for differently spelled equal requests' do
      respelled = { 'payments' => base_payload['payments'].map { |p| p.to_a.reverse.to_h }, 'payer_firm_uuid' => base_payload['payer_firm_uuid'].upcase }
      respelled['payments'][1]['amount'] = '5800.50'

      expect(fingerprint(respelled)).to eq(fingerprint(base_payload))
    end

    it 'differs when any payment detail differs' do
      changed = [
        base_payload.tap { |p| p['payments'][0]['amount'] = '6250.01' },
        JSON.parse(File.read('./spec/fixtures/payload_1.json')).tap { |p| p['payments'][0]['description'] = 'other' },
        JSON.parse(File.read('./spec/fixtures/payload_1.json')).tap { |p| p['payments'].reverse! }
      ]
      original = fingerprint(JSON.parse(File.read('./spec/fixtures/payload_1.json')))

      expect(changed.map { |json| fingerprint(json) }).to all(satisfy { |f| f != original })
    end
  end

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

  describe "when payer pays itself using uppercase uuid" do
    let(:payload) { base_payload.tap { |p| p['payments'][0]['payee_firm_uuid'] = p['payer_firm_uuid'].upcase } }

    it "should raise an InvalidInputJson exception" do
      expect { subject }.to raise_exception(App::InvalidInputJson, 'same field "payee_firm_uuid"')
    end
  end

  describe "amounts" do
    subject { described_class.new(base_payload.tap { |p| p['payments'][0]['amount'] = amount }, idempotency_key:).validate!.payments.first.amount_cents }

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
end
