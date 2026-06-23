# frozen_string_literal: true

module EventWorker
  module Worker
    DISPLAY_PRECISION = 9

    def initialize(options = {})
      @options = options
      @running = true
      @context = {}
      @unsaved = 0
      @context[:init_time] = Benchmark.realtime do
        restore_last_state
        on_init
      end
      flush_log('init')
    end

    def run
      trap('TERM') { @running = false }
      trap('INT') { @running = false }
      process_new_events while @running

      @context[:exit_time] = Benchmark.realtime { on_exit }
      flush_log('exit')
    end

    def process_new_events
      FileUtils.touch('/tmp/liveness')
      sleep(3600) if File.exist?('/tmp/simulate_hang')
      events = nil
      @context[:fetch_time] = Benchmark.realtime { events = fetch_new_events }
      process(*events) unless events.nil?
    end

    # process = handle + save
    def process(*events)
      @context[:handle_size] = events.size
      @context[:handle_time] = Benchmark.realtime do
        before_handle_batch(events)
        handle_batch(events)
        after_handle_batch
      end
      if @unsaved > 0 && !skip_saving?
        @context[:save_time] = Benchmark.realtime { save }
        @unsaved = 0
      end
      flush_log('process')
    end

    def name
      self.class.name
    end

    def topics
      raise NotImplementedError
    end

    def restore_last_state
      raise NotImplementedError
    end

    def on_init; end

    def on_exit; end

    def before_handle_batch(events); end

    def before_handle(event); end

    def handle(_event)
      raise NotImplementedError
    end

    def after_handle_batch; end

    def save
      raise NotImplementedError
    end

    protected

    def fetch_new_events
      stream_reader.fetch_new(topics)
    end

    def handle_batch(events)
      events.each do |event|
        before_handle(event)
        handle(event)
        @unsaved += 1
        break unless @running
      end
    end

    def skip_saving?
      @running && @unsaved < force_save_threshold && stream_reader.slowing?
    end

    def force_save_threshold
      10_000
    end

    def flush_log(phase)
      logger.info(to_log("#{name} #{phase}"))
      @context.clear
    end

    def to_log(prefix)
      @context.reduce(prefix) { |s, (k, v)| s + " #{k}=#{format_value(v)}" }
    end

    def format_value(value)
      case value
      when Float
        format("%.#{DISPLAY_PRECISION}f", value).sub(/0+$/, '').sub(/\.$/, '.0')
      when Array
        '[' + value.map { |val| format_value(val) }.join(', ') + ']'
      when Hash
        value.to_json
      else
        value
      end
    end

    def logger
      raise NotImplementedError
    end

    def stream_reader
      raise NotImplementedError
    end
  end
end
