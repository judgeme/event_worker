# frozen_string_literal: true

module EventWorker
  module Stream
    module Message
      def self.included(base)
        base.extend ClassMethods
      end

      module ClassMethods
        attr_accessor :topic

        def size
          stream_writer.size
        end

        def first(limit = nil)
          stream_writer.first(limit:)
        end

        def last(limit = nil)
          stream_writer.last(limit:)
        end

        def all
          stream_writer.all
        end

        def each(batch_size: 1000, &block)
          cursor = nil
          loop do
            messages = stream_writer.first(limit: batch_size, after: cursor)
            messages.each(&block)
            break if messages.size < batch_size

            cursor = messages.last[:_id]
          end
        end

        def push(*objs)
          with({}).push(*objs)
        end

        def with(attributes)
          EventWorker::Stream::Criteria.new(self, with: attributes)
        end

        def after(offset)
          EventWorker::Stream::Criteria.new(self, after: offset)
        end

        def serialize(obj, **options)
          options.key?(:with) ? obj.merge(options[:with]) : obj
        end

        def stream_writer
          EventWorker.stream_writer(topic)
        end
      end
    end
  end
end
