module EventWorker
  module Utils
    class RedisLock
      LOCK_DURATION = 1.minute
      REFRESH_SCRIPT = <<~LUA.freeze
        if redis.call("get", KEYS[1]) == ARGV[1] then
          return redis.call("set", KEYS[1], ARGV[1], "EX", ARGV[2], "XX")
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
      # lock = EventWorker::Utils::RedisLock.acquire_one_of!(2, redis, 'key')
      # lock.ttl
      # lock.refresh
      # lock.release
      class << self
        def acquire_one_of!(count, redis, key, duration: LOCK_DURATION, use_lua: false)
          (1..count).each do |i|
            lock = acquire(redis, "#{key}:#{i}", index: i, duration:, use_lua:)
            return lock if lock.present?
          end

          raise "Failed to acquire lock for #{key} after #{count} attempts"
        end

        private

        def acquire(redis, key, index: nil, duration: LOCK_DURATION, use_lua: false)
          # Use time as token to know when the lock was acquired
          token = ::Time.current.iso8601
          return unless redis.set(key, token, nx: true, ex: duration)

          new(redis, key, token, index:, duration:, use_lua:)
        end
      end

      attr_reader :key, :index

      def initialize(redis, key, token, index: nil, duration: LOCK_DURATION, use_lua: false)
        @redis = redis
        @key = key
        @index = index
        @token = token
        @duration = duration
        @use_lua = use_lua
      end

      def valid?
        token_valid? && ttl > 0
      end

      def ttl
        @redis.ttl(@key)
      end

      def refresh(strict: true)
        @use_lua ? refresh_lua : refresh_redis(strict:)
      end

      def release
        @use_lua ? release_lua : release_redis
      end

      private

      def token_valid?(strict: true)
        token = @redis.get(@key)
        (token.nil? && !strict) || token == @token
      end

      def refresh_redis(strict: true)
        return false unless token_valid?(strict:)

        @redis.set(@key, @token, ex: @duration) == 'OK'
      end

      def refresh_lua
        # Use a Lua script to atomically check the token and refresh the key
        @redis.eval(REFRESH_SCRIPT, keys: [@key], argv: [@token, @duration.to_i]) == 'OK'
      end

      def release_redis
        return false unless token_valid?

        @redis.del(@key).to_i > 0
      end

      def release_lua
        # Use a Lua script to atomically check the token and delete the key
        @redis.eval(RELEASE_SCRIPT, keys: [@key], argv: [@token]).to_i > 0
      end
    end
  end
end
