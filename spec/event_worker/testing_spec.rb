# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EventWorker::Testing do
  describe '.reset in real mode' do
    let(:stream_client) { double('stream client') }
    let(:connection) { double('connection') }

    around do |example|
      original_config = EventWorker.config
      example.run
    ensure
      EventWorker.config = original_config
    end

    before do
      allow(stream_client).to receive(:with).and_yield(connection)
      EventWorker.configure { |config| config.stream_store = :redis_stream, stream_client }
      described_class.real!
    end

    after { described_class.fake! }

    it 'sends no command when no topic was faked' do
      expect { described_class.reset }.not_to raise_error
    end

    it 'deletes the faked topics with one DEL' do
      allow(connection).to receive(:call)
      EventWorker::FakedStreams.push('#topic_a', { a: 1 })
      EventWorker::FakedStreams.push('#topic_b', { b: 2 })

      described_class.reset

      expect(connection).to have_received(:call).with('DEL', '#topic_a', '#topic_b')
    end
  end

  describe '.fake!' do
    subject(:writer) { EventWorker::StreamWriters::RedisStream.new(double('stream client'), '#event_worker_spec') }

    before { described_class.fake! }

    it 'lets a writer flush with trim_messages_older' do
      writer << { name: 'x' }
      writer.flush(trim_messages_older: '1700000000000-0')

      expect(writer.all).to match([{ _id: an_event_id, name: 'x' }])
    end
  end
end
