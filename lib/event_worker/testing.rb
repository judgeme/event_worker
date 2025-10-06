# frozen_string_literal: true

module EventWorker
  if ENV['RAILS_ENV'] == 'test'

    class Testing
      @mode = nil

      class << self
        def fake!
          enable_test_mode
          @mode = :fake
        end

        def fake?
          @mode == :fake
        end

        def reset
          EventWorker::FakedStreams.clear
        end

        private

        def enable_test_mode
          return if @test_mode_enabled

          EventWorker::StreamWriters::RedisStream.prepend EventWorker::TestingStreamWriter
          @test_mode_enabled = true
        end
      end

      module Matchers
        def push_event(event)
          PushEvent.new event
        end

        class PushEvent
          include RSpec::Matchers

          def initialize(event)
            @event = event
          end

          def matches?(event_stream)
            events = EventWorker::FakedStreams.messages[event_stream.topic]
            @matcher = include({ _id: a_kind_of(String), **@event })
            @matcher.matches? events
          end

          def description
            @matcher.description
          end

          def failure_message
            @matcher.failure_message
          end
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
            messages[topic] << { _id: EventWorker::Utils::Offset.time_to_offset(Time.now), **msg }
          end
        end

        def clear
          messages.clear
        end

        def count(topic)
          messages[topic].size
        end

        def first(topic)
          messages[topic].first
        end

        def last(topic)
          messages[topic].last
        end
      end
    end

    module TestingStreamWriter
      def self.prepended(base)
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

      def first
        EventWorker::FakedStreams.first(@topic)
      end

      def last
        EventWorker::FakedStreams.last(@topic)
      end
    end

  else
    class Testing
    end
  end
end
