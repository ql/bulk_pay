class ProcessPayments

  def self.call(json)
    pp Firm.all
    pp Payment.all

    true
  end
end
