# frozen_string_literal: true

module EventWorker
  module StreamWriters
    class Base
      def initialize(db, topic)
        @db = db
        @topic = topic
        @messages = []
      end

      def <<(message)
        @messages << message
      end

      def push(*messages)
        @messages.push(*messages)
        flush
      end

      def flush(*args)
        return if @messages.empty?

        write(*args)
        @messages.clear
      end

      def size
        raise NotImplemented
      end

      def first
        raise NotImplemented
      end

      def last
        raise NotImplemented
      end

      def all
        raise NotImplemented
      end

      def each
        raise NotImplemented
      end

      def write
        raise NotImplemented
      end

      def trim
        raise NotImplemented
      end
    end
  end
end
