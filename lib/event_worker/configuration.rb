# frozen_string_literal: true

module EventWorker
  class Configuration
    attr_reader :stream_reader_class
    attr_reader :stream_writer_class
    attr_reader :stream_client
    attr_accessor :field_types
    attr_accessor :liveness_file

    def initialize
      @field_types = {}
    end

    def stream_store=(store)
      type, client = store
      case type
      when :redis_stream
        @stream_reader_class = EventWorker::StreamReaders::RedisStream
        @stream_writer_class = EventWorker::StreamWriters::RedisStream
        @stream_client = client
      end
    end
  end
end
