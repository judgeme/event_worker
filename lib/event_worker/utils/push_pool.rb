module EventWorker
  module Utils
    class PushPool
      BATCH_SIZE = 1000
      OWNER = 0
      VERSIONS = 1
      ITEMS = 2

      def initialize(num_threads: 1, wait_for_completion: false, &block)
        @num_threads = num_threads
        @wait_for_completion = wait_for_completion

        @pool = {}                                # owner_id => [items]
        @versions = {}                            # version => { owner_id => items_count }
        @completed_versions = []                  # sorted versions that have been completed
        @completed_versions_queue = Queue.new     # versions that have been completed
        @version_complete_callbacks = []          # callbacks for completed versions
        @current_version = 0
        @completed_version = 0
        @mutex = Mutex.new
        @cond_var = ConditionVariable.new

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
          items_count = 0
          @current_version += 1
          raise 'invalid client_version' unless client_version.nil? || client_version == @current_version

          version = @current_version
          @versions[version] = {}

          # Add items to pool for each owner_id
          batch.each do |owner_id, items|
            next if items.empty?

            items_count += items.size
            owner = owners.nil? ? owner_id : owners[owner_id]
            @versions[version][owner_id] = items.size
            @pool[owner_id] ||= [owner, [], {}]
            @pool[owner_id][VERSIONS] << version
            @pool[owner_id][ITEMS].merge!(items)
          end

          complete_version(version) if items_count == 0

          @cond_var.signal

          version
        end
      end

      def add_back(owner_id, owner, versions, items)
        @mutex.synchronize do
          @pool[owner_id] = [owner, versions, items]
          @cond_var.signal
        end
      end

      # Shift the first owner_id and its items from the pool
      # @param blocking [Boolean] Whether to block until there are items in the pool
      # @return [Array(Integer, Object, Array, Array), nil] [owner_id, owner, versions, items] or nil if pool is empty
      def shift(blocking: true)
        @mutex.synchronize do
          if blocking
            while @running && @pool.empty?
              @cond_var.wait(@mutex)
            end
          end

          return nil if @pool.empty?

          owner_id, data = @pool.shift
          [owner_id, data[OWNER], data[VERSIONS], data[ITEMS]]
        end
      end

      # Acknowledge processing for a owner_id in a version
      # @param version [Integer] The version to acknowledge
      # @param owner_id [Integer, String] The owner_id to acknowledge
      # @param quantity [Integer] The number of items to acknowledge
      # @return [Array(Integer, Integer), nil] [left_quantity, completed_versions] or nil if owner_id is not in the pool
      def ack(version, owner_id, quantity = nil)
        @mutex.synchronize do
          ack_one(version, owner_id, quantity)
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
          versions.zip(results).to_h
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
          @cond_var.signal
          @completed_versions_queue << nil
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
        @mutex.synchronize { @versions.any? }
      end

      # Returns the owner_ids in the pool
      # @return [Array] The owner_ids in the pool
      def owner_ids
        @mutex.synchronize { @pool.keys }
      end

      # Returns the number of items for a given owner_id
      # @param owner_id [Integer, String] The shop ID
      # @return [Integer] The number of items for the owner_id
      def count_for(owner_id)
        @mutex.synchronize { @pool.dig(owner_id, ITEMS)&.size || 0 }
      end

      # Returns the pending versions
      # @return [Array] The pending versions
      def pending_versions
        @mutex.synchronize { @versions.keys }
      end

      # Clears the pool and all version tracking
      # @return [Hash] The empty pool
      def clear
        @mutex.synchronize do
          @pool.clear
          @versions.clear
          @completed_versions.clear
          @current_version = 0
        end
      end

      private

      def run
        return if @running

        @running = true
        @num_threads.times do
          thread = Thread.new do
            while @running || (@wait_for_completion && busy?)
              data = shift
              next if data.nil?

              owner_id, owner, versions, items = data
              retry_in = @processor.call(owner_id, owner, versions, items)
              if retry_in.nil?
                ack_for(owner_id, versions)
              else
                # sleep retry_in
                add_back(owner_id, owner, versions, items)
              end
            end
          end
          thread.abort_on_exception = true
          @threads << thread
        end
        thread = Thread.new do
          while @running || !@completed_versions_queue.empty? || (@wait_for_completion && busy?)
            version = @completed_versions_queue.pop
            next if version.nil?

            @version_complete_callbacks.each { |callback| callback.call(version) }
          end
        end
        @threads << thread
        thread.abort_on_exception = true
      end

      def ack_one(version, owner_id, quantity = nil)
        return if @versions.dig(version, owner_id).nil?

        left_quantity = \
          if quantity && quantity < @versions[version][owner_id]
            @versions[version][owner_id] -= quantity
          else
            @versions[version].delete(owner_id)
            0
          end

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
          @completed_versions_queue << @completed_versions.shift
          count += 1
        end
        count
      end
    end
  end
end
