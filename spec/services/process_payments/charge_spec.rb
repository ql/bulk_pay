require 'spec_helper'

RSpec.describe ProcessPayments::Charge do
  let(:payload) { JSON.parse(File.read('./spec/fixtures/payload_1.json')) }
  let(:request) { ProcessPayments::Request.new(payload, idempotency_key: SecureRandom.uuid) }

  it 'refuses a request that was not validated' do
    expect { described_class.new(request) }.to raise_exception(ArgumentError, /validated/)
  end

  it 'accepts a validated request' do
    expect { described_class.new(request.validate!) }.not_to raise_exception
  end
end
