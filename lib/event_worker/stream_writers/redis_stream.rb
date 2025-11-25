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

      def first(limit: nil, after: nil)
        entries = @db.with do |conn|
          conn.call('XRANGE', @topic, (after.nil? ? '-' : "(#{after}"), '+', 'COUNT', limit || 1)
        end
        if limit.nil?
          entry_to_hash(*entries.first) unless entries.empty?
        else
          entries.map { |entry| entry_to_hash(*entry) }
        end
      end

      def last(limit: nil, after: nil)
        entries = @db.with do |conn|
          conn.call('XREVRANGE', @topic, (after.nil? ? '+' : "(#{after}"), '-', 'COUNT', limit || 1)
        end
        if limit.nil?
          entry_to_hash(*entries.first) unless entries.empty?
        else
          entries.map { |entry| entry_to_hash(*entry) }
        end
      end

      def all
        entries = @db.with do |conn|
          conn.call('XRANGE', @topic, '-', '+')
        end
        entries.map { |entry| entry_to_hash(*entry) }
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

      # TODO: Refactor to avoid hardcoding these attributes
      def str_to_val(string, attribute)
        case attribute
        when 'id', 'shop_id', 'review_id'
          string&.to_i
        when 'data'
          JSON.parse(string, symbolize_names: true) rescue string
        else
          string
        end
      end

      def entry_to_hash(id, attributes)
        data = { _id: id }
        attributes.each_slice(2) do |(attribute, value)|
          data[attribute.to_sym] = str_to_val(value, attribute)
        end
        data
      end
    end
  end
end
