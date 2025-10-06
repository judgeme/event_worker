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

        def real!
          enable_test_mode
          @mode = :real
        end

        def fake?
          @mode == :fake
        end

        def real?
          @mode == :real
        end

        def reset
          if real?
            EventWorker.config.stream_client.with do |conn|
              conn.del(*EventWorker::FakedStreams.messages.keys)
            end
          end
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
        def an_event_id
          be_an_event_id
        end

        def be_an_event_id
          BeAnEventId.new
        end

        def push_event(event)
          PushEvent.new event
        end

        class BeAnEventId
          include RSpec::Matchers::Composable

          def matches?(value)
            @value = value
            value.is_a?(String) && EventWorker::Utils::Offset.valid?(value)
          end

          def description
            'be an event id'
          end

          def failure_message
            "expected #{@value} to be an event id"
          end
        end

        class PushEvent
          include RSpec::Matchers

          def initialize(event)
            @event = event
          end

          def matches?(event_stream)
            @matcher = include({ _id: be_an_event_id, **@event })
            @matcher.matches? event_stream.all
          end

          def description
            @matcher.description
          end

          def failure_message
            @matcher.failure_message
          end

          private

          def be_an_event_id
            BeAnEventId.new
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

        def all(topic)
          messages[topic]
        end
      end
    end

    module TestingStreamWriter
      def write
        @messages.each do |message|
          EventWorker::FakedStreams.push(@topic, message)
        end
        super if EventWorker::Testing.real?
      end

      def size
        return super if EventWorker::Testing.real?

        EventWorker::FakedStreams.count(@topic)
      end

      def first
        return super if EventWorker::Testing.real?

        EventWorker::FakedStreams.first(@topic)
      end

      def last
        return super if EventWorker::Testing.real?

        EventWorker::FakedStreams.last(@topic)
      end

      def all
        return super if EventWorker::Testing.real?

        EventWorker::FakedStreams.all(@topic)
      end
    end

  else
    class Testing
    end
  end
end
