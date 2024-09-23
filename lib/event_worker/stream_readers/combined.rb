# frozen_string_literal: true

module EventWorker
  module StreamReaders
    class Combined
      def initialize(stream_readers, &block)
        @stream_readers = stream_readers
        @block = block
      end

      def fetch_new(topics = nil)
        messages = []
        @stream_readers.each do |name, stream_reader|
          filtered_topics = (topics || stream_reader.offsets.keys).select { |topic| @block.call(topic) == name }
          next if filtered_topics.empty?

          msgs = stream_reader.fetch_new(filtered_topics)
          messages.concat(msgs) if msgs.present?
        end
        messages
      end

      def slowing?
        @stream_readers.any? { |_, stream_reader| stream_reader.slowing? }
      end
    end
  end
end
