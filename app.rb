require './app/requires.rb'

class App
  class << self
    attr_writer :logger

    def logger = @logger ||= Logger.new($stderr)
  end

  def self.call(env)
    req = Rack::Request.new(env)

    return [404, {"content-type" => "text/plain"}, ["Not found"]] unless req.path == '/bulk_payments'
    return [405, {"content-type" => "text/plain"}, ["Method Not Allowed"]] unless req.post?

    raw_body = req.body.read
    payload = JSON.parse(raw_body)

    # main service call
    case ProcessPayments.new(payload, idempotency_key: env['HTTP_IDEMPOTENCY_KEY']).call
    in :created
      [201, {"content-type" => "text/plain"}, ["Created"]]
    in :replayed
      [201, {"content-type" => "text/plain", "idempotent-replayed" => "true"}, ["Created"]]
    in :insufficient_balance
      [422, {"content-type" => "text/plain"}, ["Insufficient balance"]]
    end
  rescue JSON::ParserError, App::InvalidInputJson => e
    [400, {"content-type" => "text/plain"}, ["Invalid JSON submitted: #{e.message}"]]
  rescue App::IdempotencyKeyReused => e
    [422, {"content-type" => "text/plain"}, [e.message]]
  rescue ActiveRecord::RecordNotFound => e
    [404, {"content-type" => "text/plain"}, ["Not found: #{e.message}"]]
  rescue App::ConcurrencyError, ActiveRecord::ConnectionTimeoutError => e
    [503, {"content-type" => "text/plain"}, ["Error: #{e.message}"]]
  rescue => e
    logger.error(e.full_message(highlight: false))
    [500, {"content-type" => "text/plain"}, ["Service error"]]
  ensure
    # Rails returns connections to the pool after each request via its executor, plain Rack has to do it itself.
    # Without this, any lease_connection call pins a connection to the puma thread for good.
    ActiveRecord::Base.connection_handler.clear_active_connections!
  end
end

