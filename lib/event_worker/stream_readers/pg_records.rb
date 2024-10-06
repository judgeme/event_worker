# frozen_string_literal: true

module EventWorker
  module StreamReaders
    class PgRecords < Base
      def initialize(includes: [], **options)
        super(nil, **options)
        @includes = includes
      end

      def fetch(topics)
        topics.map do |topic|
          klass = topic.constantize
          records = klass.where(klass.arel_table[:id].gt(offsets[topic] || 0)).order(:id).limit(@batch_size)
          records = records.includes(*@includes) if @includes.any?
          [topic, records]
        end
      end

      def each_entry_with_topic(response)
        response.each do |(topic, records)|
          records.each do |record|
            data = { id: record.id, record: record }
            yield(topic, record.id, data)
          end
        end
      end
    end
  end
end
