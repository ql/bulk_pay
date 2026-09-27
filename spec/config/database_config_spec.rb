require 'spec_helper'

RSpec.describe 'database config' do
  let(:pool) { ActiveRecord::Base.connection_pool }

  it 'sizes the pool from MAX_THREADS, same as puma threads' do
    expect(pool.size).to eq(Integer(ENV.fetch('MAX_THREADS', 5)))
  end

  it 'kills transactions left idle so they cannot hold firm locks forever' do
    value = ActiveRecord::Base.with_connection { |c| c.select_value('SHOW idle_in_transaction_session_timeout') }
    expect(value).to eq('10s')
  end
end
