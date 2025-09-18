module EventWorker
  module Utils
    class RedisLock
      LOCK_DURATION = 1.minute

      #@example
      # lock = EventWorker::Utils::RedisLock.acquire(redis, 'key', 1.minute)
      # lock.ttl
      # lock.refresh(1.minute)
      # lock.release
      class << self
        def acquire(redis, key, duration = LOCK_DURATION)
          token = Time.current.iso8601
          return unless redis.set(key, token, nx: true, ex: duration)

          new(redis, key, token)
        end
      end

      def initialize(redis, key, token)
        @redis = redis
        @key = key
        @token = token
      end

      def ttl
        @redis.ttl(@key)
      end

      def refresh(duration = LOCK_DURATION)
        @redis.set(@key, @token, ex: duration, xx: true)
      end

      def release
        value = @redis.get(@key)
        return false unless value == @token

        @redis.del(@key).present?
      end
    end
  end
end
