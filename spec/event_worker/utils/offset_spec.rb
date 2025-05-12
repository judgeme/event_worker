require 'rails_helper'

describe EventWorker::Utils::Offset do
  describe '.compare' do
    let(:offset_a) { '123-1' }
    let(:offset_b) { '123-0' }
    subject(:result) { described_class.compare(offset_a, offset_b) }

    context 'A is nil' do
      let(:offset_a) { nil }
      it { is_expected.to eq(-1) }
    end

    context 'B is nil' do
      let(:offset_b) { nil }
      it { is_expected.to eq(1) }
    end

    context 'both A and B are nil' do
      let(:offset_a) { nil }
      let(:offset_b) { nil }
      it { is_expected.to eq(0) }
    end

    context 'milliseconds A < milliseconds B' do
      let(:offset_a) { '1697819303625-1' }
      let(:offset_b) { '1697819303626-0' }
      it { is_expected.to eq(-1) }
    end

    context 'milliseconds A > milliseconds B' do
      let(:offset_a) { '1697819303625-0' }
      let(:offset_b) { '1697819303624-1' }
      it { is_expected.to eq(1) }
    end

    context 'milliseconds A == milliseconds B' do
      context 'sequence number A < sequence number B' do
        let(:offset_a) { '1697819303625-0' }
        let(:offset_b) { '1697819303625-1' }
        it { is_expected.to eq(-1) }
      end

      context 'sequence number A > sequence number B' do
        let(:offset_a) { '1697819303625-2' }
        let(:offset_b) { '1697819303625-1' }
        it { is_expected.to eq(1) }
      end

      context 'sequence number A = sequence number B' do
        let(:offset_a) { '1697819303625-0' }
        let(:offset_b) { '1697819303625-0' }
        it { is_expected.to eq(0) }
      end
    end
  end

  describe '.min' do
    let(:offsets) do
      [
        '1697819303625-1',
        '1697819303626-0',
        '1697819303625-0',
        '1697819303624-1',
        '1697819303625-2'
      ]
    end
    subject(:result) { described_class.min(offsets) }

    it { is_expected.to eq('1697819303624-1') }

    context 'offsets are empty' do
      let(:offsets) { [] }
      it { is_expected.to eq(nil) }
    end

    context 'offsets contain only 1 offset' do
      let(:offsets) { ['1697819303625-2'] }
      it { is_expected.to eq('1697819303625-2') }
    end
  end

  describe '.time_to_offset' do
    let(:time) { '2023-10-20T16:28:23.625441018Z'.to_time }
    subject(:offset) { described_class.time_to_offset(time) }

    it { is_expected.to eq('1697819303625-0') }
  end

  describe '.offset_to_time' do
    subject(:time) { described_class.offset_to_time(offset) }
    let(:offset) { "#{expected_time.strftime('%Q')}-#{sequence}" }
    let(:sequence) { Faker::Number.number(digits: 3) }
    let(:expected_time) { DateTime.now }

    it 'converts an offset string to a DateTime' do
      expect(time.strftime('%Q')).to eq(expected_time.strftime('%Q'))
    end

    context 'when very large timestamps' do
      let(:expected_time) { DateTime.now + 100.years }

      it 'handles very large timestamps' do
        expect(time.strftime('%Q')).to eq(expected_time.strftime('%Q'))
      end
    end

    context 'when very small timestamps' do
      let(:expected_time) { DateTime.now - 50.years }

      it 'handles very small timestamps' do
        expect(time.strftime('%Q')).to eq(expected_time.strftime('%Q'))
      end
    end

    context 'when no sequence number' do
      let(:offset) { "#{expected_time.strftime('%Q')}" }

      it 'handles offsets with no sequence number' do
        expect(time.strftime('%Q')).to eq(expected_time.strftime('%Q'))
      end
    end

    context 'when multiple hyphens' do
      let(:offset) { "#{expected_time.strftime('%Q')}-123-456" }

      it 'handles offsets with multiple hyphens' do
        expect(time.strftime('%Q')).to eq(expected_time.strftime('%Q'))
      end
    end

    context 'when non-numeric timestamps' do
      let(:offset) { "abc-123" }

      it 'raises an error for non-numeric timestamps' do
        expect { time }.to raise_error(ArgumentError)
      end
    end
  end
end
