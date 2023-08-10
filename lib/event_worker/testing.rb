# frozen_string_literal: true

module EventWorker
  class Testing
    @mode = nil

    class << self
      def fake!
        @mode = :fake
      end

      def fake?
        @mode == :fake
      end

      def reset
        EventWorker::FakedStreams.clear
      end
    end
  end

  class FakedStreams
    cattr_accessor :messages do
      Hash.new { |h, topic| h[topic] = [] }
    end

    class << self
      def push(topic, *msgs)
        msgs.each do |msg|
          messages[topic] << msg
        end
      end

      def clear
        messages.clear
      end

      def count(topic)
        messages[topic].size
      end
    end
  end

  module TestingStreamWriter
    def self.included(base)
      base.alias_method :origin_write, :write
    end

    def write
      @messages.each do |message|
        EventWorker::FakedStreams.push(@topic, message)
      end
      origin_write unless EventWorker::Testing.fake?
    end

    def size
      EventWorker::FakedStreams.count(@topic)
    end
  end
end

EventWorker::StreamWriters::RedisStream.prepend EventWorker::TestingStreamWriter

if defined?(Rails) && Rails.respond_to?(:env) && !Rails.env.test?
  Rails.logger.warn('⛔️ WARNING: EventWorker testing API enabled, but this is not the test environment.')
end
