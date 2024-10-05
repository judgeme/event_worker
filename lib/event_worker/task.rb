# frozen_string_literal: true

module EventWorker
  class Task
    def initialize(backlog: 1, exit_signal: :stop, &block)
      @input = SizedQueue.new(backlog)
      @exit_signal = exit_signal
      @thread = Thread.new {
        loop do
          args = @input.pop
          break if args == @exit_signal

          block.call(*args)
        end
      }
      @thread.abort_on_exception = true
    end

    def call(*args)
      @input.push(args)
    end

    def on_exit
      @input.push(@exit_signal)
      @thread.join
    end
  end
end
