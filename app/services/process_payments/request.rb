class ProcessPayments
  # validation phase: parses and normalizes the request, knows nothing about the database
  class Request
    AMOUNT_FORMAT = /\A(\d+)(?:\.(\d{1,2}))?\z/
    UUID_FORMAT = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/
    IDEMPOTENCY_KEY_FORMAT = /\A[\x21-\x7E]{1,255}\z/
    MAX_DESCRIPTION_LENGTH = 500
    MAX_PAYMENTS = 1000 # bounds lock hold time and insert statement size

    Item = Data.define(:payee_uuid, :amount_cents, :description)

    attr_reader :payer_uuid, :payments, :idempotency_key, :fingerprint

    def initialize(json, idempotency_key:)
      @json = json
      @idempotency_key = idempotency_key
    end

    def validate!
      return self if validated?

      validate_idempotency_key
      @payer_uuid = validate_payer
      @payments = validate_payments.map { |p| build_payment(p) }
      @fingerprint = Digest::SHA256.hexdigest(JSON.generate([payer_uuid, payments.map(&:deconstruct)]))
      @validated = true
      freeze
    end

    def validated? = !!@validated

    def total_cents = payments.sum(&:amount_cents)

    def firm_uuids = [payer_uuid, *payments.map(&:payee_uuid)].uniq

    private

    def invalid!(message) = raise(App::InvalidInputJson, message)

    def validate_idempotency_key
      invalid!('missing header "Idempotency-Key"') unless idempotency_key
      invalid!('invalid header "Idempotency-Key"') unless IDEMPOTENCY_KEY_FORMAT.match?(idempotency_key)
    end

    # uuids are case-insensitive, while firms come from db as lowercase
    def validate_payer
      invalid!('request body must be a JSON object') unless @json.is_a?(Hash)
      invalid!('missing field "payer_firm_uuid"') unless @json['payer_firm_uuid']
      invalid!('invalid field "payer_firm_uuid"') unless uuid?(@json['payer_firm_uuid'])
      @json['payer_firm_uuid'].downcase
    end

    def validate_payments
      payments = @json['payments']
      invalid!('missing field "payments"') unless payments.is_a?(Array)
      invalid!('empty field "payments"') if payments.empty?
      invalid!("too many payments, max #{MAX_PAYMENTS}") if payments.size > MAX_PAYMENTS
      payments
    end

    def build_payment(p)
      invalid!('payment must be a JSON object') unless p.is_a?(Hash)
      invalid!('missing field "amount"') unless p['amount']
      invalid!('missing field "payee_firm_uuid"') unless p['payee_firm_uuid']
      invalid!('invalid field "payee_firm_uuid"') unless uuid?(p['payee_firm_uuid'])

      payee_uuid = p['payee_firm_uuid'].downcase
      invalid!('same field "payee_firm_uuid"') if payee_uuid == payer_uuid
      invalid!('missing field "description"') unless p['description']
      invalid!('invalid field "description"') unless valid_description?(p['description'])

      Item.new(payee_uuid:, amount_cents: parse_amount(p['amount']), description: p['description'])
    end

    def uuid?(value) = value.is_a?(String) && UUID_FORMAT.match?(value)

    def valid_description?(value) = value.is_a?(String) && value.length <= MAX_DESCRIPTION_LENGTH

    # not using Money gem or such to keep surface small
    # accepts only strings like "300", "5.5", "9.99" - floats are ambiguous for money
    def parse_amount(dollars_amount)
      match = AMOUNT_FORMAT.match(dollars_amount) if dollars_amount.is_a?(String)
      invalid!("wrong amount format #{dollars_amount}") unless match

      dollars, cents = match.captures
      amount = dollars.to_i * 100 + cents.to_s.ljust(2, '0').to_i
      invalid!("wrong amount format #{dollars_amount}") unless amount.positive?

      amount
    end
  end
end
