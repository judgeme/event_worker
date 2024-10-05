# frozen_string_literal: true

module EventWorker
  module StreamReaders
    BATCH_SIZE = 1000
    BLOCK_MSEC = 2000

    class Base
      attr_reader :offsets

      def initialize(db, offsets:, batch_size: BATCH_SIZE, block_msec: BLOCK_MSEC)
        @db = db
        @offsets = offsets.dup
        @last_fetched = Hash.new(0)
        @batch_size = batch_size
        @block_msec = block_msec
      end

      def fetch_new(topics = nil)
        @last_fetched.clear
        response = fetch(topics || @offsets.keys)
        return if response.nil?

        messages = []
        each_entry_with_topic(response) do |topic, id, data|
          messages << { _topic: topic, _id: id, **data }
          @offsets[topic] = id
          @last_fetched[topic] += 1
        end
        messages
      end

      def fetch(_topics)
        raise NotImplemented
      end

      def each_entry_with_topic(_response)
        raise NotImplemented
      end

      def slowing?
        @last_fetched.any? { |_topic, count| count >= @batch_size }
      end
    end
  end
end
