# frozen_string_literal: true

module EventWorker
  module Worker
    DISPLAY_PRECISION = 9

    def initialize(options = {})
      @options = options
      @running = true
      @context = {}
      @unsaved = 0
    end

    def run
      @context[:init_time] = Benchmark.realtime do
        restore_last_state
        on_init
      end
      flush_log('init')

      trap('TERM') { @running = false }
      trap('INT') { @running = false }
      while @running
        # process = fetch + handle + save
        events = nil
        @context[:fetch_time] = Benchmark.realtime { events = fetch_events }
        next if events.blank?

        @context[:handle_size] = events.size
        @context[:handle_time] = handle_batch(events)
        @context[:save_time] = Benchmark.realtime { save_with_callback } unless skip_saving?
        flush_log('process_events')
      end

      @context[:exit_time] = Benchmark.realtime do
        save_with_callback
        on_exit
      end
      flush_log('exit')
    end

    def handle_batch(events)
      [
        Benchmark.realtime do
          before_handle_batch(events)
        end,
        Benchmark.realtime do
          events.each do |event|
            before_handle(event)
            handle(event)
            after_handle
            break unless @running
          end
        end,
        Benchmark.realtime do
          after_handle_batch
        end
      ]
    end

    def save_with_callback
      save
      after_save
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

    def after_handle
      @unsaved += 1
    end

    def after_handle_batch; end

    def save
      raise NotImplementedError
    end

    def after_save
      @unsaved = 0
    end

    protected

    def fetch_events
      stream_reader.fetch_new(topics)
    end

    def skip_saving?
      stream_reader.slowing? && @unsaved < force_save_threshold
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
