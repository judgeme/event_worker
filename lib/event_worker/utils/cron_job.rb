module EventWorker
  module Utils
    class CronJob
      def self.every(interval, &block)
        new(interval, &block)
      end

      def initialize(interval, &block)
        @interval = interval
        @block = block
      end

      def offset=(offset)
        time = EventWorker::Utils::Offset.offset_to_time(offset)
        if @tick_time.nil? || time > @tick_time
          @tick_time = EventWorker::Utils::Time.tick_time(@interval, time)
          @block.call(@from_offset, @to_offset, offset) if @from_offset.present?
          @from_offset = offset
        end
        @to_offset = offset
      end
    end
  end
end
