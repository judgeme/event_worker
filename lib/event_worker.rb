# frozen_string_literal: true

module EventWorker
  class << self
    # EventWorker.config will be nullified by Rails reloading if define EventWorker in lib/ folder.
    # So move the module here to avoid being reloaded.
    attr_accessor :config

    def configure
      configuration = EventWorker::Configuration.new
      yield(configuration)
      self.config = configuration
    end

    def stream_reader(offsets)
      config.stream_reader_class.new(config.stream_client, offsets: offsets)
    end

    def stream_writer(topic)
      config.stream_writer_class.new(config.stream_client, topic)
    end
  end
end
