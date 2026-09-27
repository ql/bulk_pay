require 'spec_helper'

RSpec.describe Firm, type: :model do
  subject do
    described_class.new(
      name: 'Horns & Hooves Inc', 
      balance_cents: 10000,
      uuid: not_seeded_uuid
    )
  end

  let(:not_seeded_uuid) { 'aa819b12-f953-40ed-b4fe-68b30729cc6e' }

  it { is_expected.to be_valid }

  describe 'Rails validates' do
    it 'uniqueness' do
      subject.save!

      duplicate = described_class.new(
        name: 'Horns & Hooves Inc Copy', 
        balance_cents: 10000,
        uuid: not_seeded_uuid
      )

      expect(duplicate).not_to be_valid
    end

    it 'positiveness of balance' do
      subject.balance_cents = -1000
      expect(subject).not_to be_valid
    end
  end

  describe 'DB validates' do
    before { seed_data }

    it 'positiveness of balance' do
      expect { described_class.update_all(balance_cents: -1000) }.to raise_exception(ActiveRecord::CheckViolation)
    end
  end
end
