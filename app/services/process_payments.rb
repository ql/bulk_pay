class ProcessPayments
  attr_reader :json, :idempotency_key

  def initialize(json, idempotency_key:)
    @json = json
    @idempotency_key = idempotency_key
  end

  def call
    request = Request.new(json, idempotency_key:)
    request.validate!

    Charge.new(request).call
  end
end
