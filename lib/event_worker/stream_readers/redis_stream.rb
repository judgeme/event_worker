# frozen_string_literal: true

module EventWorker
  module StreamReaders
    class RedisStream < Base
      def fetch(topics)
        @db.call(
          'XREAD', 'COUNT', @batch_size, 'BLOCK', @block_msec,
          'STREAMS', *topics, *offsets.values_at(*topics).map { |id| id || '$' }
        )
      end

      def each_entry(res)
        res.each do |(topic, entries)|
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
