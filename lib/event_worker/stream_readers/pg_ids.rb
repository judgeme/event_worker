# frozen_string_literal: true

module EventWorker
  module StreamReaders
    class PgIds < Base
      def fetch(topics)
        topics.map do |topic|
          klass = topic.constantize
          ids = klass.where(klass.arel_table[:id].gt(offsets[topic] || 0)).order(:id).limit(@batch_size).pluck(:id)
          [topic, ids]
        end
      end

      def each_entry_with_topic(response)
        response.each do |(topic, ids)|
          ids.each do |id|
            data = { id: id }
            yield(topic, id, data)
          end
        end
      end
    end
  end
end
