# frozen_string_literal: true

module EventWorker
  module StreamReaders
    class RedisStream < Base
      def fetch(topics)
        @db.with do |conn|
          conn.call(
            'XREAD', 'COUNT', @batch_size, 'BLOCK', @block_msec,
            'STREAMS', *topics, *offsets.values_at(*topics).map { |id| id || '0-0' }
          )
        end
      end

      def each_entry_with_topic(response)
        response.each do |(topic, entries)|
          entries.each do |(id, attributes)|
            data = {}
            attributes.each_slice(2) do |(attribute, value)|
              data[attribute.to_sym] = value
            end
            yield(topic, id, data)
          end
        end
      end
    end
  end
end
