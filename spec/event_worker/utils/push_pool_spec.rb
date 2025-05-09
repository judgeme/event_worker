# frozen_string_literal: true

require 'rails_helper'

module EventWorker
  module Utils
    describe PushPool do
      let(:push_pool) { described_class.new(logger: Logger.new(STDOUT), &processor) }
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

      describe 'thread safety' do
        it 'handles concurrent access' do
          threads = []
          10.times do |i|
            threads << Thread.new do
              push_pool.add({ i => { i => "item#{i}" } })
            end
          end
          threads.each(&:join)

          expect(push_pool.size).to eq(10)
          expect(push_pool.instance_variable_get(:@current_version)).to eq(10)
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
