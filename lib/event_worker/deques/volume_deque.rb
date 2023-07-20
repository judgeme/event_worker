# frozen_string_literal: true

module EventWorker
  module Deques
    class VolumeDeque
      def initialize(time_period, zero: 0.to_d)
        @time_period = time_period
        @zero = zero
        @deque = []
        @old_accumulated_value = zero
      end

      def refresh(time = Time.now)
        @old_accumulated_value = @deque.shift[0] while !@deque.empty? && time - @deque[0][1] >= @time_period
      end

      def add(val, time = Time.now)
        @deque << [val + (@deque.empty? ? @old_accumulated_value : @deque[-1][0]), time]
      end

      def value
        @deque.empty? ? @zero : (@deque[-1][0] - @old_accumulated_value)
      end
    end
  end
end
