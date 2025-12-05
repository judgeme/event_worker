require 'rails_helper'

describe EventWorker::Utils::CronJob do
  let(:cron_job) { described_class.every(interval, &block) }
  let(:interval) { 60 }
  let(:block) { proc {} }

  describe '#offset=' do
    let(:block_calls) { [] }
    let(:block) { proc { |from, to, current| block_calls << { from:, to:, current: } } }
    let(:base_time) { Time.utc(2024, 1, 15, 12, 30, 45) }

    context 'when setting offset for the first time' do
      let(:offset) { EventWorker::Utils::Offset.time_to_offset(base_time) }

      it 'does not call the block and sets from_offset, to_offset' do
        cron_job.offset = offset

        expect(block_calls).to be_empty
        expect(cron_job.instance_variable_get(:@from_offset)).to eq(offset)
        expect(cron_job.instance_variable_get(:@to_offset)).to eq(offset)
      end
    end

    context 'when setting offset within the same tick window' do
      let(:first_offset) { EventWorker::Utils::Offset.time_to_offset(base_time) }
      let(:second_offset) { EventWorker::Utils::Offset.time_to_offset(base_time + 10.seconds) }

      it 'does not call the block and updates to_offset' do
        cron_job.offset = first_offset
        cron_job.offset = second_offset

        expect(block_calls).to be_empty
        expect(cron_job.instance_variable_get(:@from_offset)).to eq(first_offset)
        expect(cron_job.instance_variable_get(:@to_offset)).to eq(second_offset)
      end
    end

    context 'when setting offset that crosses a tick boundary' do
      let(:first_offset) { EventWorker::Utils::Offset.time_to_offset(base_time) }
      let(:second_offset) { EventWorker::Utils::Offset.time_to_offset(base_time + 61.seconds) }

      it 'calls the block and updates from_offset, to_offset' do
        cron_job.offset = first_offset
        cron_job.offset = second_offset

        expect(block_calls.size).to eq(1)
        expect(block_calls.first[:from]).to eq(first_offset)
        expect(block_calls.first[:to]).to eq(first_offset)
        expect(block_calls.first[:current]).to eq(second_offset)
        expect(cron_job.instance_variable_get(:@from_offset)).to eq(second_offset)
        expect(cron_job.instance_variable_get(:@to_offset)).to eq(second_offset)
      end
    end

    context 'when setting multiple offsets that accumulate within tick window' do
      # Use a base_time exactly at a boundary so we can accumulate within the next window
      let(:base_time) { Time.utc(2024, 1, 15, 12, 30, 0) }
      let(:first_offset) { EventWorker::Utils::Offset.time_to_offset(base_time + 5.seconds) }
      let(:second_offset) { EventWorker::Utils::Offset.time_to_offset(base_time + 10.seconds) }
      let(:third_offset) { EventWorker::Utils::Offset.time_to_offset(base_time + 65.seconds) }

      it 'calls the block with correct to_offset' do
        cron_job.offset = first_offset
        cron_job.offset = second_offset
        cron_job.offset = third_offset

        expect(block_calls.size).to eq(1)
        expect(block_calls.first[:from]).to eq(first_offset)
        expect(block_calls.first[:to]).to eq(second_offset)
        expect(block_calls.first[:current]).to eq(third_offset)
        expect(cron_job.instance_variable_get(:@from_offset)).to eq(third_offset)
        expect(cron_job.instance_variable_get(:@to_offset)).to eq(third_offset)
      end
    end

    context 'when setting offset that goes backwards in time' do
      let(:first_offset) { EventWorker::Utils::Offset.time_to_offset(base_time + 60.seconds) }
      let(:second_offset) { EventWorker::Utils::Offset.time_to_offset(base_time) }

      it 'does not call the block' do
        cron_job.offset = first_offset
        cron_job.offset = second_offset

        expect(block_calls).to be_empty
      end
    end

    context 'with 5 minute interval' do
      let(:interval) { 300 }
      let(:first_offset) { EventWorker::Utils::Offset.time_to_offset(base_time) }
      let(:second_offset) { EventWorker::Utils::Offset.time_to_offset(base_time + 301.seconds) }

      it 'calls the block when crossing 5 minute boundary' do
        cron_job.offset = first_offset
        cron_job.offset = second_offset

        expect(block_calls.size).to eq(1)
      end
    end

    context 'with multiple tick boundaries crossed' do
      let(:first_offset) { EventWorker::Utils::Offset.time_to_offset(base_time) }
      let(:second_offset) { EventWorker::Utils::Offset.time_to_offset(base_time + 61.seconds) }
      let(:third_offset) { EventWorker::Utils::Offset.time_to_offset(base_time + 122.seconds) }

      it 'calls the block for each boundary crossing' do
        cron_job.offset = first_offset
        cron_job.offset = second_offset
        expect(block_calls.size).to eq(1)

        cron_job.offset = third_offset
        expect(block_calls.size).to eq(2)
      end
    end
  end
end
