# frozen_string_literal: true

module EventWorker
  module Stream
    class Criteria
      def initialize(klass, **options)
        @klass = klass
        @options = options
      end

      def push(*objs)
        @klass.stream_writer.push(*objs.map { |obj| @klass.serialize(obj, **@options) })
      end

      def first(limit = nil)
        @klass.stream_writer.first(limit:, **@options)
      end

      def last(limit = nil)
        @klass.stream_writer.last(limit:, **@options)
      end
    end
  end
end
