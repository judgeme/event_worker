# frozen_string_literal: true

module EventWorker
  class Context < Hash
    DISPLAY_PRECISION = 3

    class << self
      def logger
        @logger ||= Logger.new(STDOUT)
      end

      def logger=(logger)
        @logger = logger
      end
    end

    def initialize(name, ...)
      @name = name
      super(...)
      @log = {}
    end

    def flush
      self.class.logger&.info(to_log)
      clear
    end

    def clear
      super
      @log.clear
    end

    def log(hash)
      @log.merge!(hash)
    end

    def benchmark(key)
      @log[key] = Benchmark.realtime { yield }
    end

    private

    def to_log
      @log.reduce(@name) { |s, (k, v)| s + " #{k}=#{format_value(v)}" }
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
  end
end
