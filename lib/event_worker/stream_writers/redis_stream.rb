# frozen_string_literal: true

module EventWorker
  module StreamWriters
    class RedisStream < Base
      def write(trim_messages_older: nil)
        @db.with do |conn|
          conn.pipelined do
            @messages.each_with_index do |message, index|
              trim_option = index.zero? && !trim_messages_older.nil? ? ['MINID', trim_messages_older] : []
              conn.call('XADD', @topic, *trim_option, '*', *message.compact.map { |k, v| [k, val_to_str(v)] })
            end
          end
        end
      end

      def trim(messages_older:)
        return if messages_older.nil?

        @db.with do |conn|
          conn.call('XTRIM', @topic, 'MINID', messages_older)
        end
      end

      def size
        @db.with do |conn|
          conn.call('XLEN', @topic)
        end
      end

      def first
        @db.with do |conn|
          conn.xrange(@topic, '-', '+', count: 1).first
        end
      end

      def last
        @db.with do |conn|
          conn.xrevrange(@topic, '+', '-', count: 1).first
        end
      end

      private

      def val_to_str(value)
        case value
        when Hash, Array
          value.to_json
        else
          value.to_s
        end
      end
    end
  end
end
