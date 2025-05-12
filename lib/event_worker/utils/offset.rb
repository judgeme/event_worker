# frozen_string_literal: true

module EventWorker
  module Utils
    module Offset
      class << self
        def compare(offset_a, offset_b)
          timestamp_a, sequence_a = (offset_a || '0-0').split('-')
          timestamp_b, sequence_b = (offset_b || '0-0').split('-')
          compared_timestamp = timestamp_a.to_i <=> timestamp_b.to_i
          compared_timestamp.zero? ? sequence_a.to_i <=> sequence_b.to_i : compared_timestamp
        end

        def min(offsets)
          offsets.min { |offset_a, offset_b| compare(offset_a, offset_b) }
        end

        def time_to_offset(time)
          time.strftime('%s%3N-0')
        end

        def offset_to_time(offset)
          timestamp, _sequence = offset.split('-')
          DateTime.strptime(timestamp, '%Q')
        end
      end
    end
  end
end
