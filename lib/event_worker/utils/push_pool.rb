module EventWorker
  module Utils
    class PushPool
      BATCH_SIZE = 1000

      def initialize
        @pool = {}                         # owner_id => [items]
        @versions = {}                     # version => { owner_id => items_count }
        @completed_versions = []           # sorted versions that have been completed
        @version_complete_callbacks = []   # callbacks for completed versions
        @current_version = 0
        @completed_version = 0
        @mutex = Mutex.new
        @cond_var = ConditionVariable.new
      end

      # Add items to the pool for a batch of owner_ids, and assign a version to the batch
      # - if the owner_id is not in the pool, it will be added
      # - if the owner_id is already in the pool, the item will be added to the array
      # @param batch [Hash] A hash of owner_id => [item, item, ...]
      # @return [Integer] The version assigned to this batch
      def add(batch)
        return if batch.empty?

        @mutex.synchronize do
          # Increment version for this batch
          version = @current_version += 1
          @versions[version] = {}

          # Add items to pool for each owner_id
          batch.each do |owner_id, items|
            @pool[owner_id] ||= []
            @versions[version][owner_id] = items.size
            items.each do |item|
              @pool[owner_id] << [version, item]
            end
          end

          @cond_var.signal

          version
        end
      end

      # Shift the first owner_id and its first limit items from the pool
      # @param blocking [Boolean] Whether to block until there are items in the pool
      # @param limit [Integer] The number of items to shift
      # @return [Array(Integer, Array), nil] [owner_id, items] or nil if pool is empty
      def shift(blocking: true, limit: BATCH_SIZE)
        @mutex.synchronize do
          if blocking
            while @pool.empty?
              @cond_var.wait(@mutex)
            end
          end

          return nil if @pool.empty?

          # Get the first owner_id and its items from the pool
          owner_id, items = @pool.shift

          # If the owner_id has more than limit items, push the remaining items back to the pool
          if items.size > limit
            left_items = items.pop(items.size - limit)
            @pool[owner_id] = left_items
          end

          [owner_id, items]
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
      # @param items [Array] The items to acknowledge
      # @return [Hash] The results of the acknowledgements
      def ack_for(owner_id, items)
        quantities = Hash.new(0)
        items.each do |(version, _item)|
          quantities[version] += 1
        end
        @mutex.synchronize do
          results = quantities.map do |version, quantity|
            ack_one(version, owner_id, quantity)
          end
          quantities.keys.zip(results).to_h
        end
      end

      # Register a callback to be called when a version is complete
      # @param block [Proc] The callback to call with the completed version
      # @return [Array] The array of callbacks
      def on_version_complete(&block)
        @version_complete_callbacks << block
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

      # Returns the owner_ids in the pool
      # @return [Array] The owner_ids in the pool
      def owner_ids
        @mutex.synchronize { @pool.keys }
      end

      # Returns the number of items for a given owner_id
      # @param owner_id [Integer, String] The shop ID
      # @return [Integer] The number of items for the owner_id
      def count_for(owner_id)
        @mutex.synchronize { (@pool[owner_id] || []).size }
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
          @completed_version = @completed_versions.shift
          @version_complete_callbacks.each { |callback| callback.call(@completed_version) }
          count += 1
        end
        count
      end
    end
  end
end
