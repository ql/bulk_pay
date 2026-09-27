class App
  class InvalidInputJson < StandardError; end
  class ConcurrencyError < StandardError; end
  class IdempotencyKeyReused < StandardError; end
end
