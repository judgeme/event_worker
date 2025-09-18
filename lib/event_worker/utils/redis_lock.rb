module EventWorker
  module Utils
    class RedisLock
      LOCK_DURATION = 5.minutes
      REFRESH_SCRIPT = <<~LUA.freeze
        if redis.call("get", KEYS[1]) == ARGV[1] then
          return redis.call("set", KEYS[1], ARGV[1], "EX", ARGV[2])
        else
          return 0
        end
      LUA
      RELEASE_SCRIPT = <<~LUA.freeze
        if redis.call("get", KEYS[1]) == ARGV[1] then
          return redis.call("del", KEYS[1])
        else
          return 0
        end
      LUA

      #@example
      # lock, index = EventWorker::Utils::RedisLock.acquire_one_of!(2, redis, 'key', 1.minute)
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
          # Use time as token to know when the lock was acquired
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
        # Use a Lua script to atomically check the token and refresh the key
        @redis.eval(REFRESH_SCRIPT, keys: [@key], argv: [@token, duration]).to_i > 0
      end

      def release
        # Use a Lua script to atomically check the token and delete the key
        @redis.eval(RELEASE_SCRIPT, keys: [@key], argv: [@token]).to_i > 0
      end
    end
  end
end
