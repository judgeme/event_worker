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
        entry = @db.with do |conn|
          conn.call('XRANGE', @topic, '-', '+', 'COUNT', 1).first
        end
        entry_to_hash(*entry) unless entry.nil?
      end

      def last
        entry = @db.with do |conn|
          conn.call('XREVRANGE', @topic, '+', '-', 'COUNT', 1).first
        end
        entry_to_hash(*entry) unless entry.nil?
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

      def entry_to_hash(id, attributes)
        data = { _id: id }
        attributes.each_slice(2) do |(attribute, value)|
          data[attribute.to_sym] = value
        end
        data
      end
    end
  end
end
