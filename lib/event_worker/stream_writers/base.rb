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

      def flush
        raise NotImplemented
      end
    end
  end
end
