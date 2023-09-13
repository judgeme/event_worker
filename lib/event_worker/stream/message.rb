# frozen_string_literal: true

module EventWorker
  module Stream
    module Message
      def self.included(base)
        base.extend ClassMethods
      end

      module ClassMethods
        def size
          stream_writer.size
        end

        def push(*objs)
          with({}).push(*objs)
        end

        def with(attributes)
          EventWorker::Stream::Criteria.new(
            stream_writer: stream_writer, serializer: method(:serialize), with: attributes
          )
        end

        def serialize(obj, **options)
          options.key?(:with) ? obj.merge(options[:with]) : obj
        end
      end
    end
  end
end
