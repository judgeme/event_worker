# frozen_string_literal: true

require 'json'
require 'logger'
require 'benchmark'
require 'fileutils'
require 'set'
require 'zlib'
require 'date'
require 'bigdecimal/util'

require 'active_support'
require 'active_support/core_ext'

require_relative 'event_worker/version'
require_relative 'event_worker/configuration'
require_relative 'event_worker/context'
require_relative 'event_worker/deques/volume_deque'
require_relative 'event_worker/error'
require_relative 'event_worker/stream/criteria'
require_relative 'event_worker/stream/message'
require_relative 'event_worker/stream_readers/base'
require_relative 'event_worker/stream_readers/combined'
require_relative 'event_worker/stream_readers/pg_ids'
require_relative 'event_worker/stream_readers/pg_records'
require_relative 'event_worker/stream_readers/redis_stream'
require_relative 'event_worker/stream_writers/base'
require_relative 'event_worker/stream_writers/redis_stream'
require_relative 'event_worker/task'
require_relative 'event_worker/utils/cron_job'
require_relative 'event_worker/utils/offset'
require_relative 'event_worker/utils/partitioner'
require_relative 'event_worker/utils/push_pool'
require_relative 'event_worker/utils/redis_lock'
require_relative 'event_worker/utils/time'
require_relative 'event_worker/worker'
require_relative 'event_worker/worker/v2'

module EventWorker
  class << self
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
      config.stream_writer_class.new(config.stream_client, topic, field_types: config.field_types)
    end
  end
end
