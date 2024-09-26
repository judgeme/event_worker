# frozen_string_literal: true

module EventWorker
  class Context < Hash
    DISPLAY_PRECISION = 9

    def initialize(...)
      super(...)
      @log = {}
    end

    def name=(name)
      @name = name
    end

    def logger=(logger)
      @logger = logger
    end

    def flush
      @logger&.info("#{@name} #{to_log}")
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
