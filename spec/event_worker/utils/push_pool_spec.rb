# frozen_string_literal: true

require 'rails_helper'

module EventWorker
  module Utils
    describe PushPool do
      let(:push_pool) { described_class.new(width_limit: width_limit, height_limit: height_limit, logger: EventWorker::Context.logger, &processor) }
      let(:width_limit) { 3 }
      let(:height_limit) { 5 }
      let(:processor) { nil }
      let(:owner_id_1) { 1 }
      let(:owner_id_2) { 2 }
      let(:owner_id_3) { 3 }
      let(:items_1) { { 1 => 'item1', 2 => 'item2' } }
      let(:items_2) { { 3 => 'item3', 4 => 'item4' } }
      let(:items_3) { { 5 => 'item5', 6 => 'item6' } }

      describe '#initialize' do
        it 'initializes with empty pool and version tracking' do
          expect(push_pool.instance_variable_get(:@pool)).to eq({})
          expect(push_pool.instance_variable_get(:@versions)).to eq({})
          expect(push_pool.instance_variable_get(:@completed_versions)).to eq([])
          expect(push_pool.instance_variable_get(:@version_complete_callbacks)).to eq([])
          expect(push_pool.instance_variable_get(:@current_version)).to eq(0)
        end
      end

      describe '#add' do
        subject(:version) { push_pool.add(batch) }
        let(:batch) { { owner_id_1 => items_1, owner_id_2 => items_2 } }

        it 'adds items to the pool and returns version number' do
          expect(version).to eq(1)
          expect(push_pool.instance_variable_get(:@pool)).to eq(
            owner_id_1 => [owner_id_1, [1], items_1],
            owner_id_2 => [owner_id_2, [1], items_2]
          )
          expect(push_pool.instance_variable_get(:@versions)).to eq(
            1 => { owner_id_1 => items_1.size, owner_id_2 => items_2.size }
          )
        end

        context 'when batch data is empty' do
          let(:batch) { {} }

          it 'still returns a version number' do
            expect(version).to eq(1)
          end
        end

        context 'when batch data has empty items' do
          let(:batch) { { owner_id_1 => items_1, owner_id_2 => {} } }

          it 'skips empty item array' do
            expect(version).to eq(1)
            expect(push_pool.instance_variable_get(:@pool)).to eq(
              owner_id_1 => [owner_id_1, [1], items_1]
            )
            expect(push_pool.instance_variable_get(:@versions)).to eq(
              1 => { owner_id_1 => items_1.size }
            )
          end
        end

        context 'when batch data has existing owner_id' do
          let(:batch) { { owner_id_1 => items_2 } }

          before { push_pool.add({ owner_id_1 => items_1 }) }

          it 'adds items to the pool and returns version number' do
            expect(version).to eq(2)
            expect(push_pool.instance_variable_get(:@pool)).to eq(
              owner_id_1 => [owner_id_1, [1, 2], items_1.merge(items_2)]
            )
            expect(push_pool.instance_variable_get(:@versions)).to eq(
              1 => { owner_id_1 => items_1.size },
              2 => { owner_id_1 => items_2.size }
            )
          end
        end

        context 'when adding multiple batches' do
          it 'increments version for each batch' do
            expect(push_pool.add({ owner_id_1 => items_1 })).to eq(1)
            expect(push_pool.add({ owner_id_2 => items_2 })).to eq(2)
            expect(push_pool.add({ owner_id_3 => items_3 })).to eq(3)
            expect(push_pool.instance_variable_get(:@pool)).to eq(
              owner_id_1 => [owner_id_1, [1], items_1],
              owner_id_2 => [owner_id_2, [2], items_2],
              owner_id_3 => [owner_id_3, [3], items_3]
            )
          end
        end
      end

      describe '#shift' do
        subject(:result) { push_pool.shift(blocking:) }
        let(:blocking) { true }

        context 'when pool is empty' do
          let(:blocking) { false }

          it 'returns nil' do
            expect(result).to be_nil
          end
        end

        context 'when pool is not empty' do
          before do
            push_pool.add({ owner_id_1 => items_1 })
          end

          it 'returns owner_id and all items' do
            expect(result).to eq([owner_id_1, owner_id_1, [1], items_1])
            expect(push_pool.instance_variable_get(:@pool)[owner_id_1]).to be_nil
          end
        end
      end

      describe '#ack_for' do
        subject(:result) do
          owner_id, _owner, versions, _items = push_pool.shift
          push_pool.ack_for(owner_id, versions)
        end
        let!(:version_1) { push_pool.add({ owner_id_1 => items_1 }) }
        let!(:version_2) { push_pool.add({ owner_id_2 => items_2 }) }
        let!(:version_3) { push_pool.add({ owner_id_1 => items_3 }) }

        context 'when completing multiple versions' do
          it 'completes the version' do
            expect(result).to eq(
              version_1 => [0, 1],
              version_3 => [0, 0]
            )
          end
        end
      end

      describe '#on_version_complete' do
        let(:processor) { ->(*_args) { nil } }

        it 'registers callback for completed versions' do
          callback_called = false
          push_pool.on_version_complete { |version| callback_called = (version == 1) }

          push_pool.add({ owner_id_1 => items_1 })
          push_pool.ack_for(owner_id_1, [1])
          push_pool.stop

          expect(callback_called).to be true
        end

        it 'supports multiple callbacks' do
          versions = []
          push_pool.on_version_complete { |version| versions << version }
          push_pool.on_version_complete { |version| versions << version * 10 }

          push_pool.add({ owner_id_1 => items_1 })
          push_pool.ack_for(owner_id_1, [1])
          push_pool.stop

          expect(versions).to eq([1, 10])
        end
      end

      describe '#size' do
        it 'returns number of owner_ids in pool' do
          expect(push_pool.size).to eq(0)

          push_pool.add({ owner_id_1 => items_1, owner_id_2 => items_2 })
          expect(push_pool.size).to eq(2)

          push_pool.shift
          expect(push_pool.size).to eq(1)
        end
      end

      describe '#empty?' do
        it 'returns true if pool is empty' do
          expect(push_pool.empty?).to be true

          push_pool.add({ owner_id_1 => items_1 })
          expect(push_pool.empty?).to be false

          push_pool.shift
          expect(push_pool.empty?).to be true
        end
      end

      describe '#count_for' do
        it 'returns number of items for owner_id' do
          expect(push_pool.count_for(owner_id_1)).to eq(0)

          push_pool.add({ owner_id_1 => items_1 })
          expect(push_pool.count_for(owner_id_1)).to eq(2)
        end
      end

      describe 'thread safety' do
        let(:width_limit) { 100 }

        it 'handles concurrent access' do
          threads = []
          width_limit.times do |i|
            threads << Thread.new do
              push_pool.add({ i => { i => "item#{i}" } })
            end
          end
          threads.each(&:join)

          expect(push_pool.size).to eq(width_limit)
          expect(push_pool.instance_variable_get(:@current_version)).to eq(width_limit)
        end
      end

      describe 'width and height limits' do
        it 'initializes with the specified width and height limits' do
          expect(push_pool.instance_variable_get(:@width_limit)).to eq(width_limit)
          expect(push_pool.instance_variable_get(:@height_limit)).to eq(height_limit)
        end

        context 'when reaching width limit' do
          it 'blocks when adding more owner_ids than the width limit' do
            # Fill the pool to the width limit
            width_limit.times do |i|
              push_pool.add({ i => { i => "item_#{i}" } })
            end

            # Verify the pool is at width limit
            expect(push_pool.size).to eq(width_limit)

            # Set up a thread to add another owner_id
            thread_completed = false
            thread = Thread.new do
              push_pool.add({ (width_limit + 1) => { (width_limit + 1) => 'new_item' } })
              thread_completed = true
            end

            # Verify the thread is blocked
            sleep 0.1
            expect(thread_completed).to be false
            expect(thread.status).to eq('sleep')

            # Shift an item to make room
            push_pool.shift

            # Verify the thread completes
            sleep 0.1
            expect(thread_completed).to be true
            expect(push_pool.size).to eq(width_limit)
          end
        end

        context 'when reaching height limit' do
          it 'blocks when adding more items than the height limit for an owner_id' do
            # Add items up to just below the height limit
            push_pool.add({ owner_id_1 => (height_limit - 1).times.map { |i| [i + 1, "item_#{i}"] }.to_h })

            # Verify the items count
            expect(push_pool.count_for(owner_id_1)).to eq(height_limit - 1)

            # Set up a thread to add more items to the same owner_id
            thread_completed = false
            thread = Thread.new do
              push_pool.add({ owner_id_1 => { (height_limit + 1) => 'overflow_item1', (height_limit + 2) => 'overflow_item2' } })
              thread_completed = true
            end

            # Verify the thread is blocked
            sleep 0.1
            expect(thread_completed).to be false
            expect(thread.status).to eq('sleep')

            # Shift items to make room
            push_pool.shift

            # Verify the thread completes
            sleep 0.1
            expect(thread_completed).to be true
          end
        end

        it 'allows adding items after shifting to make room' do
          # Fill the pool to the width limit
          width_limit.times do |i|
            push_pool.add({ i => { i => ["item_#{i}"] } })
          end

          # Shift an item to make room
          push_pool.shift

          # Add a new owner_id
          version = push_pool.add({ -1 => { -1 => ['new_item'] } })

          # Verify the new item was added
          expect(push_pool.size).to eq(width_limit)
          expect(push_pool.instance_variable_get(:@versions)).to include(version)
        end

        it 'signals waiting threads when items are shifted' do
          # Fill the pool to the width limit
          width_limit.times do |i|
            push_pool.add({ i => { i => ["item_#{i}"] } })
          end

          # Set up multiple threads waiting to add items
          threads = []
          thread_completed = Array.new(3, false)

          3.times do |i|
            threads << Thread.new do
              idx = i
              push_pool.add({ (width_limit + idx) => { (width_limit + idx) => ["waiting_item_#{idx}"] } })
              thread_completed[idx] = true
            end
          end

          # Verify the threads are blocked
          sleep 0.1
          expect(thread_completed.count(true)).to eq(0)

          # Shift items one by one and verify threads complete in order
          width_limit.times do |i|
            push_pool.shift
            sleep 0.1
            expect(thread_completed.count(true)).to eq(i + 1)
          end

          # Clean up
          threads.each(&:join)
        end
      end

      describe '#complete_version' do
        let(:processor) { ->(*_args) { nil } }

        it 'processes versions in order' do
          completed_versions = []
          push_pool.on_version_complete { |version| completed_versions << version }

          # Set up versions manually to test the private method
          push_pool.instance_variable_set(:@versions, { 1 => { owner_id_1 => 1 }, 2 => { owner_id_2 => 2 }, 3 => { owner_id_3 => 3 } })

          # Call the private method directly
          push_pool.send(:complete_version, 2)

          # Version 2 should be in completed_versions but not processed yet
          expect(push_pool.instance_variable_get(:@completed_versions)).to eq([2])
          expect(completed_versions).to be_empty

          # Complete version 1
          push_pool.send(:complete_version, 1)
          push_pool.stop

          # Now versions 1 and 2 should be processed
          expect(completed_versions).to eq([1, 2])
          expect(push_pool.instance_variable_get(:@versions)).to eq({ 3 => { owner_id_3 => 3 } })
        end
      end
    end
  end
end
