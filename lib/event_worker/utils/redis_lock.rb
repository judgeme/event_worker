module EventWorker
  module Utils
    class RedisLock
      LOCK_DURATION = 5.minutes

      #@example
      # lock = EventWorker::Utils::RedisLock.acquire(redis, 'key', 1.minute)
      # lock.ttl
      # lock.refresh(1.minute)
      # lock.release
      class << self
        def acquire_one_of!(count, redis, key, duration = LOCK_DURATION)
          (1..count).each do |i|
            lock = acquire(redis, "#{key}:#{i}", duration)
            return [lock, i] if lock.present?
          end

          raise "Failed to acquire lock for #{key} after #{count} attempts"
        end

        private

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
