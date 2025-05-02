# frozen_string_literal: true

require 'rails_helper'

module EventWorker
  module Utils
    describe PushPool do
      let(:push_pool) { described_class.new }
      let(:owner_id_1) { 1 }
      let(:owner_id_2) { 2 }
      let(:owner_id_3) { 3 }
      let(:items_1) { ['item1', 'item2'] }
      let(:items_2) { ['item3', 'item4'] }
      let(:items_3) { ['item5', 'item6'] }

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
            owner_id_1 => items_1.map { |item| [1, item] },
            owner_id_2 => items_2.map { |item| [1, item] }
          )
          expect(push_pool.instance_variable_get(:@versions)).to eq(
            1 => { owner_id_1 => items_1.size, owner_id_2 => items_2.size }
          )
        end

        context 'when batch data is empty' do
          let(:batch) { {} }

          it 'returns nil' do
            expect(version).to be_nil
          end
        end

        context 'when batch data has empty item arrays' do
          let(:batch) { { owner_id_1 => items_1, owner_id_2 => [] } }

          it 'does not skip empty item arrays' do
            expect(version).to eq(1)
            expect(push_pool.instance_variable_get(:@pool)).to eq(
              owner_id_1 => items_1.map { |item| [1, item] },
              owner_id_2 => []
            )
            expect(push_pool.instance_variable_get(:@versions)).to eq(
              1 => { owner_id_1 => items_1.size, owner_id_2 => 0 }
            )
          end
        end

        context 'when batch data has existing owner_id' do
          let(:batch) { { owner_id_1 => items_2 } }

          before { push_pool.add({ owner_id_1 => items_1 }) }

          it 'adds items to the pool and returns version number' do
            expect(version).to eq(2)
            expect(push_pool.instance_variable_get(:@pool)).to eq(
              owner_id_1 => items_1.map { |item| [1, item] } + items_2.map { |item| [2, item] }
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
              owner_id_1 => items_1.map { |item| [1, item] },
              owner_id_2 => items_2.map { |item| [2, item] },
              owner_id_3 => items_3.map { |item| [3, item] }
            )
          end
        end
      end

      describe '#shift' do
        subject(:result) { push_pool.shift(limit: items_1.size) }

        context 'when pool is empty' do
          it 'returns nil' do
            expect(result).to be_nil
          end
        end

        context 'when owner_id has less than limit items' do
          before do
            push_pool.add({ owner_id_1 => items_1 })
          end

          it 'returns owner_id and all items' do
            expect(result).to eq([owner_id_1, items_1.map { |item| [1, item] }])
            expect(push_pool.instance_variable_get(:@pool)[owner_id_1]).to be_nil
          end
        end

        context 'when owner_id has more than limit items' do
          before do
            push_pool.add({ owner_id_1 => items_1 + items_2 })
          end

          it 'returns owner_id and limit items' do
            expect(result).to eq([owner_id_1, items_1.map { |item| [1, item] }])
            expect(push_pool.instance_variable_get(:@pool)[owner_id_1]).to eq(items_2.map { |item| [1, item] })
          end
        end
      end

      describe '#ack' do
        subject(:result) { push_pool.ack(version, owner_id, quantity) }
        let(:owner_id) { owner_id_1 }
        let(:quantity) { nil }

        context 'when version does not exist' do
          let(:version) { 999 }
          it { is_expected.to be nil }
        end

        context 'when version exists' do
          let(:version) { version_1 }
          let!(:version_1) { push_pool.add(owner_id_1 => items_1, owner_id_2 => items_2) }

          context 'when owner_id does not exist in version' do
            let(:owner_id) { 999 }
            it { is_expected.to be nil }
          end

          context 'when owner_id exists in version' do
            it 'removes owner_id from version' do
              expect(result).to eq([0, 0])
              expect(push_pool.instance_variable_get(:@versions)).to eq(
                version_1 => { owner_id_2 => items_2.size }
              )
            end

            context 'when quantity is specified' do
              let(:quantity) { 1 }

              it 'reduces quantity from owner_id' do
                expect(result).to eq([items_1.size - 1, 0])
                expect(push_pool.instance_variable_get(:@versions)).to eq(
                  version_1 => { owner_id_1 => items_1.size - 1, owner_id_2 => items_2.size }
                )
              end
            end

            context 'when owner_id is the last one in version' do
              before { push_pool.ack(version, owner_id_2) }

              it 'completes the version' do
                expect(result).to eq([0, 1])
                expect(push_pool.instance_variable_get(:@versions)).to be_empty
              end
            end
          end
        end

        context 'when multiple versions exist' do
          let!(:version_1) { push_pool.add(owner_id_1 => items_1) }
          let!(:version_2) { push_pool.add(owner_id_2 => items_2) }

          context 'when smallest version is completed' do
            let(:version) { version_1 }

            it 'completes the version' do
              expect(result).to eq([0, 1])
              expect(push_pool.instance_variable_get(:@versions)).to eq(
                version_2 => { owner_id_2 => items_2.size }
              )
              expect(push_pool.instance_variable_get(:@completed_versions)).to be_empty
            end
          end

          context 'when non-smallest version is completed' do
            let(:version) { version_2 }
            let(:owner_id) { owner_id_2 }

            it 'does not complete the version' do
              expect(result).to eq([0, 0])
              expect(push_pool.instance_variable_get(:@versions)).to eq(
                version_1 => { owner_id_1 => items_1.size }
              )
              expect(push_pool.instance_variable_get(:@completed_versions)).to eq([version_2])
            end
          end
        end
      end

      describe '#on_version_complete' do
        it 'registers callback for completed versions' do
          callback_called = false
          push_pool.on_version_complete { |version| callback_called = (version == 1) }

          push_pool.add({ owner_id_1 => items_1 })
          push_pool.ack(1, owner_id_1)

          expect(callback_called).to be true
        end

        it 'supports multiple callbacks' do
          versions = []
          push_pool.on_version_complete { |version| versions << version }
          push_pool.on_version_complete { |version| versions << version * 10 }

          push_pool.add({ owner_id_1 => items_1 })
          push_pool.ack(1, owner_id_1)

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

      describe '#owner_ids' do
        it 'returns owner_ids in pool' do
          expect(push_pool.owner_ids).to be_empty

          push_pool.add({ owner_id_1 => items_1, owner_id_2 => items_2 })
          expect(push_pool.owner_ids).to contain_exactly(owner_id_1, owner_id_2)
        end
      end

      describe '#count_for' do
        it 'returns number of items for owner_id' do
          expect(push_pool.count_for(owner_id_1)).to eq(0)

          push_pool.add({ owner_id_1 => items_1 })
          expect(push_pool.count_for(owner_id_1)).to eq(2)
        end
      end

      describe '#pending_versions' do
        it 'returns pending versions' do
          expect(push_pool.pending_versions).to be_empty

          push_pool.add({ owner_id_1 => items_1 })
          push_pool.add({ owner_id_2 => items_2 })

          expect(push_pool.pending_versions).to eq([1, 2])
        end
      end

      describe '#clear' do
        it 'clears pool and version tracking' do
          push_pool.add({ owner_id_1 => items_1 })
          push_pool.clear

          expect(push_pool.instance_variable_get(:@pool)).to be_empty
          expect(push_pool.instance_variable_get(:@versions)).to be_empty
          expect(push_pool.instance_variable_get(:@completed_versions)).to be_empty
          expect(push_pool.instance_variable_get(:@current_version)).to eq(0)
        end
      end

      describe 'thread safety' do
        it 'handles concurrent access' do
          threads = []
          10.times do |i|
            threads << Thread.new do
              push_pool.add({ i => ["item#{i}"] })
            end
          end
          threads.each(&:join)

          expect(push_pool.size).to eq(10)
          expect(push_pool.instance_variable_get(:@current_version)).to eq(10)
        end
      end

      describe 'complete_version' do
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

          # Now versions 1 and 2 should be processed
          expect(completed_versions).to eq([1, 2])
          expect(push_pool.instance_variable_get(:@versions)).to eq({ 3 => { owner_id_3 => 3 } })
        end
      end
    end
  end
end
