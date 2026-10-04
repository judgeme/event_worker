# frozen_string_literal: true

require 'securerandom'
require 'connection_pool'
require 'redis'
require 'event_worker'
require 'event_worker/testing'

REDIS_URL = ENV.fetch('REDIS_URL', 'redis://localhost:6379/15')

EventWorker.configure do |config|
  config.stream_store = :redis_stream, ConnectionPool.new { Redis.new(url: REDIS_URL) }
end
EventWorker::Context.logger = nil

module RedisHelper
  def redis
    @redis ||= Redis.new(url: REDIS_URL)
  end
end

RSpec.configure do |config|
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.include RedisHelper
  config.include EventWorker::Testing::Matchers

  config.before(:suite) do
    EventWorker::Testing.fake!
  end

  config.after do
    EventWorker::Testing.reset
  end
end
