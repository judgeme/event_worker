# frozen_string_literal: true

module EventWorker
  class Task
    attr_reader :input
    attr_accessor :next_task

    def initialize(backlog: 1, exit_signal: :stop, &block)
      if backlog <= 0
        @block = block
        return
      end

      @input = SizedQueue.new(backlog)
      @exit_signal = exit_signal
      @thread = Thread.new {
        loop do
          args = @input.pop
          break if args == @exit_signal

          value = block.call(*args)
          call_next(value)
        end
      }
      @thread.abort_on_exception = true
    end

    def call(*args)
      if @input.nil?
        value = @block.call(*args)
        call_next(value)
      else
        @input.push(args)
      end
    end

    def call_next(value)
      return if value.nil? || @next_task.nil?

      value.is_a?(Array) ? @next_task.call(*value) : @next_task.call(value)
    end

    def after(task)
      task.next_task = self
    end

    def on_exit
      @input&.push(@exit_signal)
      @thread&.join
    end
  end
end
