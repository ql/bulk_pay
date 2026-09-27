require 'spec_helper'

RSpec.describe Payment, type: :model do

  subject do
    described_class.new(
      payer_firm_id: 1,
      payee_firm_id: 2,
      amount_cents: 10000,
      description: 'payment 1', 
    )
  end

  it { is_expected.to be_valid }

  describe 'rails validates' do
    it 'negative amount' do
      subject.amount_cents = -1000
      expect(subject).not_to be_valid
    end

    it 'self payment is not allowed' do
      subject.payer_firm_id = subject.payee_firm_id
      expect(subject).not_to be_valid
    end
  end

  describe 'DB validations' do
    before do 
      seed_data
      subject.save
    end

    it 'prevent negative amounts' do
      expect { described_class.update_all(amount_cents: -1000) }.to raise_exception(ActiveRecord::CheckViolation)
    end

    it 'prevent self payment' do
      expect { described_class.update_all('payer_firm_id = payee_firm_id') }.to raise_exception(ActiveRecord::CheckViolation)
    end

    it 'requires both firms' do
      expect { described_class.update_all(payer_firm_id: nil) }.to raise_exception(ActiveRecord::NotNullViolation)
      expect { described_class.update_all(payee_firm_id: nil) }.to raise_exception(ActiveRecord::NotNullViolation)
    end

    it 'maintains integrity' do
      subject.save!
      expect { subject.payer_firm.destroy }.to raise_exception(ActiveRecord::InvalidForeignKey)
      expect { subject.payee_firm.destroy }.to raise_exception(ActiveRecord::InvalidForeignKey)
    end
  end
end
