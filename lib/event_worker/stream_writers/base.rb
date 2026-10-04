# frozen_string_literal: true

module EventWorker
  module StreamWriters
    class Base
      def initialize(db, topic, field_types: {})
        @db = db
        @topic = topic
        @field_types = field_types
        @messages = []
      end

      def <<(message)
        @messages << message
      end

      def push(*messages)
        @messages.push(*messages)
        flush
      end

      def flush(...)
        return if @messages.empty?

        write(...)
        @messages.clear
      end

      def size
        raise NotImplementedError
      end

      def first
        raise NotImplementedError
      end

      def last
        raise NotImplementedError
      end

      def all
        raise NotImplementedError
      end

      def each
        raise NotImplementedError
      end

      def write
        raise NotImplementedError
      end

      def trim
        raise NotImplementedError
      end
    end
  end
end
