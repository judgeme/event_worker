# frozen_string_literal: true

module EventWorker
  module Stream
    class Criteria
      def initialize(stream_writer:, serializer:, **options)
        @stream_writer = stream_writer
        @serializer = serializer
        @options = options
      end

      def push(*objs)
        @stream_writer.push(*objs.map { |obj| @serializer.call(obj, @options) })
      end
    end
  end
end
