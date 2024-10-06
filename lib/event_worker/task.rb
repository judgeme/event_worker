# frozen_string_literal: true

module EventWorker
  class Task
    attr_reader :input
    attr_accessor :output

    def initialize(output: nil, backlog: 1, exit_signal: :stop, &block)
      @input = SizedQueue.new(backlog)
      @output = output
      @exit_signal = exit_signal
      @thread = Thread.new {
        loop do
          args = @input.pop
          break if args == @exit_signal

          value = block.call(*args)
          @output&.push(value.is_a?(Array) ? value : [value]) unless value.nil?
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
