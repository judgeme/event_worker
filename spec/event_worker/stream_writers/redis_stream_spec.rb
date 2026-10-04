# frozen_string_literal: true

require 'rails_helper'

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
end
