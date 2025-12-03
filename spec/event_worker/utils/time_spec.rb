require 'rails_helper'

describe EventWorker::Utils::Time do
  describe '.tick_time' do
    subject(:result) { described_class.tick_time(resolution, time, time_offset:, offset:) }

    let(:time_offset) { 0 }
    let(:offset) { 1 }

    context 'with 60 second resolution' do
      let(:resolution) { 60 }

      context 'when time is at 12:30:45' do
        let(:time) { Time.utc(2024, 1, 15, 12, 30, 45) }

        context 'with default offset of 1' do
          it 'returns the next minute boundary' do
            expect(result).to eq(Time.utc(2024, 1, 15, 12, 31, 0))
          end
        end

        context 'with offset of 0' do
          let(:offset) { 0 }

          it 'returns the current minute boundary' do
            expect(result).to eq(Time.utc(2024, 1, 15, 12, 30, 0))
          end
        end

        context 'with offset of 2' do
          let(:offset) { 2 }

          it 'returns two minutes ahead' do
            expect(result).to eq(Time.utc(2024, 1, 15, 12, 32, 0))
          end
        end
      end

      context 'when time is exactly on a boundary' do
        let(:time) { Time.utc(2024, 1, 15, 12, 30, 0) }

        it 'returns the next boundary' do
          expect(result).to eq(Time.utc(2024, 1, 15, 12, 31, 0))
        end
      end
    end

    context 'with 300 second (5 minute) resolution' do
      let(:resolution) { 300 }
      let(:time) { Time.utc(2024, 1, 15, 12, 33, 45) }

      it 'returns the next 5-minute boundary' do
        expect(result).to eq(Time.utc(2024, 1, 15, 12, 35, 0))
      end

      context 'with offset of 0' do
        let(:offset) { 0 }

        it 'returns the current 5-minute boundary' do
          expect(result).to eq(Time.utc(2024, 1, 15, 12, 30, 0))
        end
      end
    end

    context 'with 3600 second (1 hour) resolution' do
      let(:resolution) { 3600 }
      let(:time) { Time.utc(2024, 1, 15, 12, 45, 30) }

      it 'returns the next hour boundary' do
        expect(result).to eq(Time.utc(2024, 1, 15, 13, 0, 0))
      end
    end

    context 'with time_offset' do
      let(:resolution) { 60 }
      let(:time_offset) { 15 }
      let(:time) { Time.utc(2024, 1, 15, 12, 30, 45) }

      it 'offsets the calculation by time_offset seconds' do
        # time_offset shifts the boundaries to :15 marks
        # 12:30:45 -> bucket starts at 12:30:15, next is 12:31:15
        expect(result).to eq(Time.utc(2024, 1, 15, 12, 31, 15))
      end

      context 'when time is at 12:30:10 (before the :15 boundary)' do
        let(:time) { Time.utc(2024, 1, 15, 12, 30, 10) }

        it 'returns the next aligned boundary' do
          # 12:30:10 is in the 12:29:15-12:30:15 bucket, next is 12:30:15
          expect(result).to eq(Time.utc(2024, 1, 15, 12, 30, 15))
        end
      end
    end

    context 'with fractional seconds' do
      let(:resolution) { 60 }
      let(:time) { Time.utc(2024, 1, 15, 12, 30, 45.5) }

      it 'handles fractional seconds correctly' do
        expect(result).to eq(Time.utc(2024, 1, 15, 12, 31, 0))
      end
    end

    context 'with negative offset' do
      let(:resolution) { 60 }
      let(:time) { Time.utc(2024, 1, 15, 12, 30, 45) }
      let(:offset) { -1 }

      it 'returns a previous boundary' do
        expect(result).to eq(Time.utc(2024, 1, 15, 12, 29, 0))
      end
    end

    context 'crossing midnight boundary' do
      let(:resolution) { 3600 }
      let(:time) { Time.utc(2024, 1, 15, 23, 30, 0) }

      it 'correctly crosses to the next day' do
        expect(result).to eq(Time.utc(2024, 1, 16, 0, 0, 0))
      end
    end

    context 'with small resolution (1 second)' do
      let(:resolution) { 1 }
      let(:time) { Time.utc(2024, 1, 15, 12, 30, 45.7) }

      it 'returns the next second' do
        expect(result).to eq(Time.utc(2024, 1, 15, 12, 30, 46))
      end
    end
  end
end
