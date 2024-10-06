# frozen_string_literal: true

module EventWorker
  module Worker
    module V2
      def initialize(backlog: 1, **options)
        @backlog = backlog
        @running = true
        @tasks = []
        context = Context.new("#{name} init").merge(options)
        context.benchmark(:init_time) do
          restore_last_state(context)
          on_init(context)
        end
        context.flush
        return if @tasks.any?

        register_task(&method(:do_handle))
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

      def before_handle_batch(context, events); end

      def before_handle(context, event); end

      def handle(context, event)
        raise NotImplementedError
      end

      def after_handle_batch(context); end

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
          before_handle_batch(context, events)
          handle_batch(context, events)
          after_handle_batch(context)
        end
        context
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

      def handle_batch(context, events)
        events.each do |event|
          value = before_handle(context, event)
          handle(context, event) unless value.is_a?(FalseClass)
          break unless @running
        end
      end

      def stream_reader
        raise NotImplementedError
      end
    end
  end
end
