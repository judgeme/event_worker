module EventWorker
  module Utils
    class Partitioner
      RAND_BASE = 2**32 - 1

      class << self
        def between?(user_id, from_percent, to_percent)
          !in_percent?(user_id, from_percent) && in_percent?(user_id, to_percent)
        end

        private

        def in_percent?(user_id, percent)
          Zlib.crc32(user_id.to_s) < RAND_BASE * percent
        end
      end

      attr_reader :from_percent, :to_percent

      def initialize(partition_count, partition_id)
        @from_percent = (partition_id - 1) / partition_count.to_f
        @to_percent = partition_id / partition_count.to_f
      end

      def accept?(user_id)
        EventWorker::Utils::Partitioner.between?(user_id, @from_percent, @to_percent)
      end
    end
  end
end
