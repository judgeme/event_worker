# frozen_string_literal: true

require 'spec_helper'

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

  redis_client_missing = begin
    require 'redis-client'
    nil
  rescue LoadError
    'redis-client is bundled only with redis-rb 5'
  end

  describe '.reset in real mode on a ConnectionPool of RedisClients', skip: redis_client_missing do
    let(:topics) { Array.new(2) { "#event_worker_spec:#{SecureRandom.hex(8)}" } }

    around do |example|
      original_config = EventWorker.config
      pool = ConnectionPool.new { RedisClient.new(url: REDIS_URL) }
      EventWorker.configure { |config| config.stream_store = :redis_stream, pool }
      described_class.real!
      example.run
    ensure
      described_class.fake!
      EventWorker.config = original_config
      pool&.shutdown(&:close)
      redis.del(*topics)
    end

    it 'deletes every topic written since the last reset', :aggregate_failures do
      topics.each { |topic| EventWorker.stream_writer(topic).push({ name: 'x' }) }
      expect(topics.map { |topic| redis.exists?(topic) }).to eq([true, true])

      described_class.reset

      expect(topics.map { |topic| redis.exists?(topic) }).to eq([false, false])
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
