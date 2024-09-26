# frozen_string_literal: true

module EventWorker
  class Task
    def initialize(exit_signal: :stop, &block)
      @input = SizedQueue.new(1)
      @exit_signal = exit_signal
      @thread = Thread.new {
        loop do
          value = @input.pop
          break if value == @exit_signal

          # TODO: handle exception
          block.call(value)
        end
      }
    end

    def call(value)
      @input.push(value)
    end

    def on_exit
      @input.push(@exit_signal)
      @thread.join
    end
  end
end
