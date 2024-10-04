# frozen_string_literal: true

module EventWorker
  class QueryPool
    def initialize(pool_size)
      @pool_size = pool_size
      @count = 0
      @queries = Queue.new
      @results = Queue.new
      @mutex = Mutex.new
      @threads = []
    end

    def size
      @threads.size
    end

    def query(*args, &block)
      @queries << [args, block]
      @mutex.synchronize do
        @count += 1
        @threads << spawn_thread if @queries.size > 0 && @threads.size < @pool_size
      end
    end

    def result(&block)
      @count.times do
        value = @results.pop
        block.call(value)
      end
      @count = 0
    end

    def shutdown
      @threads.each { |thread| thread.raise(Error::ExitSignal) }
      @threads.each(&:join)
    end

    private

    def spawn_thread
      thread = Thread.new do
        loop do
          args, block = @queries.pop
          @results << block.call(*args)
        rescue Error::ExitSignal
          break
        end
      end
      thread.abort_on_exception = true
      thread
    end
  end
end
