# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EventWorker::StreamWriters::RedisStream do
  let(:topic) { '#event_worker_spec' }
  let(:stream_client) { double('stream client') }
  let(:connection) { double('connection') }

  # Fake mode answers reads and writes without the connection, so the stubbed one is only reached in real mode.
  before do
    allow(stream_client).to receive(:with).and_yield(connection)
    EventWorker::Testing.real!
  end

  after { EventWorker::Testing.fake! }

  describe '#first, #last and #all' do
    let(:entry_id) { '1700000000000-0' }

    before do
      allow(connection).to receive(:call)
        .and_return([[entry_id, ['id', '42', 'shop_id', '7', 'review_id', '9', 'data', '{"rating":5}', 'notes', 'not json']]])
    end

    context 'without field_types' do
      subject(:writer) { described_class.new(stream_client, topic) }

      it 'returns every field as the string Redis stored', :aggregate_failures do
        entry = { _id: entry_id, id: '42', shop_id: '7', review_id: '9', data: '{"rating":5}', notes: 'not json' }

        expect(writer.first).to eq(entry)
        expect(writer.last).to eq(entry)
        expect(writer.all).to eq([entry])
      end
    end

    context 'with field_types' do
      subject(:writer) do
        described_class.new(stream_client, topic, field_types: { 'shop_id' => :integer, 'data' => :json, 'notes' => :json })
      end

      it 'casts only the listed fields and keeps unparsable JSON as the string', :aggregate_failures do
        entry = { _id: entry_id, id: '42', shop_id: 7, review_id: '9', data: { rating: 5 }, notes: 'not json' }

        expect(writer.first).to eq(entry)
        expect(writer.last).to eq(entry)
        expect(writer.all).to eq([entry])
      end
    end
  end

  describe '#flush' do
    subject(:writer) { described_class.new(stream_client, topic) }

    let(:pipeline) { double('pipeline', call: nil) }

    before { allow(connection).to receive(:pipelined).and_yield(pipeline) }

    it 'trims through XADD MINID when given trim_messages_older' do
      writer << { name: 'x' }
      writer.flush(trim_messages_older: '1700000000000-0')

      expect(pipeline).to have_received(:call).with('XADD', topic, 'MINID', '1700000000000-0', '*', any_args)
    end
  end

  context 'against a real Redis' do
    subject(:writer) { EventWorker.stream_writer(topic) }

    let(:topic) { "#event_worker_spec:#{SecureRandom.hex(8)}" }

    after { redis.del(topic) }

    it 'reads the stream back through size, first, last and all, not the fakes', :aggregate_failures do
      redis.xadd(topic, { name: 'seeded' }, id: '1000-0')
      writer.push({ id: 1, name: 'pushed' }, { id: 2, data: { rating: 5 } })

      stored_ids = redis.xrange(topic).map(&:first)
      seeded_entry = { _id: '1000-0', name: 'seeded' }
      pushed_entries = [
        { _id: stored_ids[1], id: '1', name: 'pushed' },
        { _id: stored_ids[2], id: '2', data: '{"rating":5}' }
      ]

      expect(stored_ids).to match(['1000-0', an_event_id, an_event_id])
      expect(writer.size).to eq(3)
      expect(writer.first).to eq(seeded_entry)
      expect(writer.last).to eq(pushed_entries.last)
      expect(writer.all).to eq([seeded_entry, *pushed_entries])
    end

    it 'trims the entries older than trim_messages_older on flush' do
      redis.xadd(topic, { seed: 'older' }, id: '1000-0')
      redis.xadd(topic, { seed: 'newer' }, id: '2000-0')

      writer << { name: 'x' }
      writer.flush(trim_messages_older: '1500-0')

      expect(redis.xrange(topic).map(&:first)).to match(['2000-0', an_event_id])
    end
  end
end
