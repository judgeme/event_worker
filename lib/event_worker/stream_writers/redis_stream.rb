# frozen_string_literal: true

module EventWorker
  module StreamWriters
    class RedisStream < Base
      def flush(delete_messages_older: nil)
        return if @messages.empty?

        @messages.each_with_index do |message, index|
          trim_option = index.zero? && !delete_messages_older.nil? ? ['MINID', delete_messages_older] : []
          @db.call('XADD', @topic, *trim_option, '*', *message.compact.map { |k, v| [k, val_to_str(v)] })
        end
        @messages.clear
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
