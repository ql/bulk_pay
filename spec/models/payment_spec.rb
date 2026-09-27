require 'spec_helper'

RSpec.describe Payment, type: :model do

  subject do
    described_class.new(
      payer_firm_id: '3f1c9a2e-7b4d-4c1e-9a55-2d8e6f0b7c41',
      payee_firm_id: '8b2e4c71-0d3a-4f6e-b1c9-5a7d2e9f4c10',
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

    it 'maintans integrity' do
      subject.save!
      expect { subject.payer_firm.destroy }.to raise_exception(ActiveRecord::InvalidForeignKey)
      expect { subject.payee_firm.destroy }.to raise_exception(ActiveRecord::InvalidForeignKey)
    end
  end
end
