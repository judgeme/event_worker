module EventWorker
  module Utils
    # Partitioner is used to partition a list of user_ids into a list of partitions.
    # It is used to ensure that each user_id is only processed by one partition.
    # It is used to ensure that each worker is processing a fair share of the user_ids.
    #
    # @example
    # partitioner = EventWorker::Utils::Partitioner.new(4, 2)
    # partitioner.from_percent # => 0.25
    # partitioner.to_percent # => 0.5
    # partitioner.accept?('user_1') # => true
    # partitioner.accept?('user_2') # => false
    # partitioner.accept?('user_3') # => false
    # partitioner.accept?('user_4') # => false
    # partitioner.accept?('user_5') # => true
    # partitioner.accept?('user_6') # => false
    # partitioner.accept?('user_7') # => false
    # partitioner.accept?('user_8') # => false
    # partitioner.accept?('user_9') # => true
    # partitioner.accept?('user_10') # => false
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
