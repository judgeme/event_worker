# frozen_string_literal: true

module EventWorker
  module Worker
    module V2
      def initialize(backlog: 1, **options)
        @backlog = backlog
        @running = true
        @unsaved = 0
        @tasks = []
        context = Context.new("#{name} init").merge(options)
        context.benchmark(:init_time) do
          restore_last_state(context)
          on_init(context)
        end
        context.flush

        register_task(&method(:do_handle))
        register_task(&method(:do_before_save))
        register_task(&method(:do_save))
      end

      def run
        trap('TERM') { @running = false }
        trap('INT') { @running = false }
        process_new_events while @running

        do_exit
      end

      def process_new_events
        events = nil
        context = Context.new("#{name} process")
        context.benchmark(:fetch_time) { events = fetch_new_events }
        @tasks.first.call(context, events) unless events.nil?
      end

      # process = handle + save
      def process(*events)
        context = Context.new("#{name} process")
        @tasks.first.call(context, events)
      end

      def name
        self.class.name
      end

      def topics
        raise NotImplementedError
      end

      def restore_last_state(context)
        raise NotImplementedError
      end

      def on_init(context); end

      def on_exit; end

      def before_handle_batch(events); end

      def before_handle(event); end

      def handle(_event)
        raise NotImplementedError
      end

      def after_handle_batch; end

      def save(context)
        raise NotImplementedError
      end

      protected

      def fetch_new_events
        stream_reader.fetch_new(topics)
      end

      # TODO: Support @backlog == 0
      def register_task(&block)
        task = @backlog > 0 ? Task.new(backlog: @backlog, &block) : block
        @tasks.last.output = task.input unless @tasks.empty?
        @tasks << task
      end

      def do_handle(context, events)
        return context unless @running

        context.log(handle_size: events.size)
        context.benchmark(:handle_time) do
          before_handle_batch(events)
          handle_batch(events)
          after_handle_batch
        end
        context
      end

      def do_before_save(context)
        if @unsaved > 0 && !skip_saving?
          @unsaved = 0
          before_save(context)
          context
        else
          context.flush
          nil
        end
      end

      def do_save(context)
        context.benchmark(:save_time) { save(context) }
        context.flush
      end

      def do_exit
        context = Context.new("#{name} exit")
        context.benchmark(:exit_time) do
          @tasks.each { |task| task.on_exit if task.respond_to?(:on_exit) }
          on_exit
        end
        context.flush
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

      def stream_reader
        raise NotImplementedError
      end
    end
  end
end
