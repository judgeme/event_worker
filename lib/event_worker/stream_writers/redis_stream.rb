# frozen_string_literal: true

module EventWorker
  module StreamWriters
    class RedisStream < Base
      def write(trim_messages_older: nil)
        @db.pipelined do
          @messages.each_with_index do |message, index|
            trim_option = index.zero? && !trim_messages_older.nil? ? ['MINID', trim_messages_older] : []
            @db.call('XADD', @topic, *trim_option, '*', *message.compact.map { |k, v| [k, val_to_str(v)] })
          end
        end
      end

      def trim(messages_older:)
        return if messages_older.nil?

        @db.call('XTRIM', @topic, 'MINID', messages_older)
      end

      def size
        @db.call('XLEN', @topic)
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
