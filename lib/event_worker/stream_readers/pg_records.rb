# frozen_string_literal: true

module EventWorker
  module StreamReaders
    class PgRecords < Base
      def initialize(includes: [], scopes: [], fields: {}, **options)
        super(nil, **options)
        @includes = includes
        @scopes = scopes
        @fields = fields
      end

      def fetch(topics)
        topics.map do |topic|
          klass = topic.constantize
          records = klass.where(klass.arel_table[:id].gt(offsets[topic] || 0)).order(:id).limit(@batch_size)
          records = records.includes(*@includes) if @includes.any?
          records = records.select(@fields[klass]) if @fields.key?(klass)
          @scopes.each do |scope|
            records = records.public_send(scope) if records.respond_to?(scope)
          end
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
