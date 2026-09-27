require 'spec_helper'

RSpec.describe 'database config' do
  let(:pool) { ActiveRecord::Base.connection_pool }

  it 'sizes the pool from MAX_THREADS, same as puma threads' do
    expect(pool.size).to eq(Integer(ENV.fetch('MAX_THREADS', 5)))
  end

  describe 'connection target' do
    def rendered_config(env)
      original = ENV.to_h.slice(*env.keys)
      env.each { |key, value| ENV[key] = value }
      YAML.load(ERB.new(File.read('config/database.yml')).result, aliases: true)['production']
    ensure
      env.each_key { |key| original.key?(key) ? ENV[key] = original[key] : ENV.delete(key) }
    end

    it 'reads host and port from env' do
      config = rendered_config('DB_HOST' => 'db.internal', 'DB_PORT' => '6432')
      expect(config.slice('host', 'port')).to eq('host' => 'db.internal', 'port' => 6432)
    end

    it 'defaults to local postgres' do
      config = rendered_config('DB_HOST' => nil, 'DB_PORT' => nil)
      expect(config.slice('host', 'port')).to eq('host' => 'localhost', 'port' => 5432)
    end
  end

  it 'kills transactions left idle so they cannot hold firm locks forever' do
    value = ActiveRecord::Base.with_connection { |c| c.select_value('SHOW idle_in_transaction_session_timeout') }
    expect(value).to eq('10s')
  end
end
