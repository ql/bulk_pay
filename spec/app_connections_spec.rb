require 'spec_helper'
require 'rack/mock'

RSpec.describe App, 'connection handling' do
  let(:pool) { ActiveRecord::Base.connection_pool }
  let(:payload) { File.read('./spec/fixtures/payload_1.json') }

  before { seed_data }

  def lease_connection = ActiveRecord::Base.lease_connection.execute('SELECT 1')

  # runs a request in a fresh thread, like a puma thread, and reports if it still holds a connection
  def holds_connection_after(&request)
    Thread.new do
      request.call
    ensure
      Thread.current[:held] = pool.active_connection?
    end.join[:held]
  ensure
    pool.reap
  end

  def post = App.call(Rack::MockRequest.env_for('/bulk_payments', method: 'POST', input: payload))

  it 'lease_connection pins a connection to the thread on its own' do
    expect(holds_connection_after { lease_connection }).to be_truthy
  end

  it 'returns a leased connection to the pool after the request' do
    allow_any_instance_of(ProcessPayments).to receive(:call) { lease_connection && true }

    expect(holds_connection_after { expect(post[0]).to eq(201) }).to be_falsey
  end

  it 'returns a leased connection to the pool when the request fails' do
    allow_any_instance_of(ProcessPayments).to receive(:call) { lease_connection && raise('boom') }

    expect(holds_connection_after { expect(post[0]).to eq(500) }).to be_falsey
  end
end
