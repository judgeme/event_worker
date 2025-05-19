module EventWorker
  module Utils
    class PushPool
      CONCURRENCY = 10
      WIDTH_LIMIT = 100
      HEIGHT_LIMIT = 1000

      BATCH_SIZE = 1000
      OWNER = 0
      VERSIONS = 1
      ITEMS = 2

      def initialize(concurrency: CONCURRENCY, width_limit: WIDTH_LIMIT, height_limit: HEIGHT_LIMIT, logger: nil, &block)
        @concurrency = concurrency
        @width_limit = width_limit
        @height_limit = height_limit
        @logger = logger

        @queued = 0
        @processing = Hash.new(0)
        @processed = 0
        @retries = Set.new
        @pool = {}                                # owner_id => [ owner, versions, items ]
        @versions = {}                            # version => { owner_id => items_count }
        @completed_versions = []                  # sorted versions that have been completed
        @completed_versions_queue = Queue.new     # versions that have been completed
        @version_complete_callbacks = []          # callbacks for completed versions
        @current_version = 0
        @completed_version = 0
        @mutex = Mutex.new
        @add_cond_var = ConditionVariable.new
        @remove_cond_var = ConditionVariable.new

        @threads = []
        @running = false
        @processor = block
        run unless @processor.nil?
      end

      # Add items to the pool for a batch of owner_ids, and assign a version to the batch
      # - if the owner_id is not in the pool, it will be added
      # - if the owner_id is already in the pool, the item will be added to the array
      # @param batch [Hash] A hash of owner_id => [item, item, ...]
      # @param owners [Hash] A hash of owner_id => owner
      # @return [Integer] The version assigned to this batch
      def add(batch, owners: nil, client_version: nil)
        @mutex.synchronize do
          @current_version += 1
          raise 'invalid client_version' unless client_version.nil? || client_version == @current_version

          items_count = 0
          version = @current_version
          @versions[version] = {}
          batch.each do |owner_id, items|
            next if items.empty?

            @queued += 1
            items_count += items.size
            @versions[version][owner_id] = items.size
          end
          if items_count == 0
            complete_version(version)
            return version
          end

          # Add items to pool for each owner_id
          batch.each do |owner_id, items|
            next if items.empty?

            wait_for_space(owner_id, items.size)
            owner = owners.nil? ? owner_id : owners[owner_id]
            @pool[owner_id] ||= [owner, [], {}]
            @pool[owner_id][VERSIONS] << version
            @pool[owner_id][ITEMS].merge!(items)
          end

          @add_cond_var.signal
          @logger&.info("PushPool#add version=#{version} width=#{batch.size} count=#{items_count}")
          version
        end
      end

      def add_back(owner_id, owner, versions, items, after: nil)
        sleep after if after.present?
        @mutex.synchronize do
          return false if reaching_limit?(owner_id, items.size)

          @pool[owner_id] ||= [owner, [], {}]
          @pool[owner_id][VERSIONS] += versions
          @pool[owner_id][ITEMS].reverse_merge!(items)
          @processing[owner_id] -= versions.size
          @processing.delete(owner_id) if @processing[owner_id] == 0
          @queued += versions.size
          versions.each do |version|
            @retries << [owner_id, version]
          end
          @add_cond_var.signal
          @logger&.warn("PushPool#add_back owner_id=#{owner_id} versions=#{versions} count=#{items.size} after=#{after}")
          true
        end
      end

      # Shift the first owner_id and its items from the pool
      # @param blocking [Boolean] Whether to block until there are items in the pool
      # @return [Array(Integer, Object, Array, Array), nil] [owner_id, owner, versions, items] or nil if pool is empty
      def shift(blocking: true)
        @mutex.synchronize do
          owner_id, data = nil, nil
          loop do
            owner_id, data = @pool.find { |id, _data| !@processing.key?(id) }
            break if owner_id.present? || !blocking || !@running

            @add_cond_var.wait(@mutex)
          end
          return nil if owner_id.nil?

          @pool.delete(owner_id)
          @queued -= data[VERSIONS].size
          @processing[owner_id] += data[VERSIONS].size
          @remove_cond_var.signal
          @logger&.debug("#{self.class.name}#shift owner_id=#{owner_id} versions=#{data[VERSIONS]} count=#{data[ITEMS].size}")
          [owner_id, data[OWNER], data[VERSIONS], data[ITEMS]]
        end
      end

      # Acknowledge processing for a owner_id in multiple versions
      # @param owner_id [Integer, String] The owner_id to acknowledge
      # @param versions [Array] The versions to acknowledge
      # @return [Hash] The results of the acknowledgements
      def ack_for(owner_id, versions)
        @mutex.synchronize do
          results = versions.map do |version|
            ack_one(version, owner_id)
          end
          results_hash = versions.zip(results).to_h
          @logger&.debug("#{self.class.name}#ack_for owner_id=#{owner_id} results=#{results_hash}")
          results_hash
        end
      end

      # Register a callback to be called when a version is complete
      # @param block [Proc] The callback to call with the completed version
      # @return [Array] The array of callbacks
      def on_version_complete(&block)
        @version_complete_callbacks << block
      end

      # Stop processing and wait for all threads to complete
      # @return [Boolean] Whether processing was stopped
      def stop
        return false unless @running

        @mutex.synchronize do
          @running = false
          @completed_versions_queue << nil
          @concurrency.times { @add_cond_var.signal }
        end

        @threads.each(&:join)
        @threads.clear

        true
      end

      # Returns the number of owner_ids in the pool
      # @return [Integer] The size of the pool
      def size
        @mutex.synchronize { @pool.size }
      end

      # Returns true if the pool is empty
      # @return [Boolean] Whether the pool is empty
      def empty?
        @mutex.synchronize { @pool.empty? }
      end

      # Returns true if any worker is busy
      # @return [Boolean] Whether any worker is busy
      def busy?
        @mutex.synchronize { @queued + @processing.values.sum - @retries.size > 0 }
      end

      # Returns the number of items for a given owner_id
      # @param owner_id [Integer, String] The shop ID
      # @return [Integer] The number of items for the owner_id
      def count_for(owner_id)
        @mutex.synchronize { @pool.dig(owner_id, ITEMS)&.size || 0 }
      end

      private

      def run
        return if @running

        @running = true
        @concurrency.times do
          thread = Thread.new do
            while @running || busy?
              data = shift
              next if data.nil?

              owner_id, owner, versions, items = data
              process(owner_id, owner, versions, items)

              # Use nil version as a signal to wake up the version completion thread
              @completed_versions_queue << nil
            end
          end
          thread.abort_on_exception = true
          @threads << thread
        end
        thread = Thread.new do
          while @running || busy? || !@completed_versions_queue.empty?
            version = @completed_versions_queue.pop
            next if version.nil?

            @version_complete_callbacks.each { |callback| callback.call(version) }
          end
        end
        thread.abort_on_exception = true
        @threads << thread
      end

      def process(owner_id, owner, versions, items)
        retry_after = @processor.call(owner_id, owner, versions, items)
        if retry_after.nil?
          ack_for(owner_id, versions)
        elsif add_back(owner_id, owner, versions, items, after: retry_after)
          nil
        else
          @logger&.warn("PushPool#process owner_id=#{owner_id} versions=#{versions} count=#{items.size} after=#{retry_after}")
          process(owner_id, owner, versions, items)
        end
      end

      def wait_for_space(owner_id, items_count)
        while reaching_limit?(owner_id, items_count)
          @remove_cond_var.wait(@mutex)
        end
      end

      def reaching_limit?(owner_id, items_count)
        (!@pool.key?(owner_id) && @pool.size >= @width_limit) || (@pool.key?(owner_id) && (@pool[owner_id][ITEMS].size + items_count) > @height_limit)
      end

      def ack_one(version, owner_id, quantity = nil)
        return if @versions.dig(version, owner_id).nil?

        ack_quantity = quantity || @versions[version][owner_id]
        left_quantity = \
          if ack_quantity < @versions[version][owner_id]
            @versions[version][owner_id] -= ack_quantity
          else
            @versions[version].delete(owner_id)
            0
          end

        @processing[owner_id] -= 1
        @processing.delete(owner_id) if @processing[owner_id] == 0
        @processed += 1
        @retries.delete([owner_id, version])

        # If version is empty, mark it as complete
        completed = @versions[version].empty? ? complete_version(version) : 0
        [left_quantity, completed]
      end

      def complete_version(version)
        @versions.delete(version)

        # Add version to completed_versions in sorted order
        insert_index = @completed_versions.bsearch_index { |v| v >= version } || @completed_versions.size
        @completed_versions.insert(insert_index, version)

        # Process completed versions in order
        count = 0
        while @completed_versions.first == (@completed_version + 1)
          @completed_version = @completed_versions.shift
          @completed_versions_queue << @completed_version
          count += 1
        end
        if count == 0
          expecting_version = @completed_version + 1
          @logger&.info("PushPool#complete_version version=#{version}#{@completed_version - version} versions[#{expecting_version}]=#{@versions[expecting_version]}")
        else
          @logger&.info("PushPool#complete_version version=#{version}#{"+#{count-1}" if count > 1}")
        end
        count
      end
    end
  end
end
