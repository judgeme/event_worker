# frozen_string_literal: true

require 'spec_helper'

describe EventWorker::Utils::Partitioner do
  describe '#initialize' do
    it 'calculates correct percentages for first partition' do
      partitioner = described_class.new(4, 1)

      expect(partitioner.instance_variable_get(:@from_percent)).to eq(0.0)
      expect(partitioner.instance_variable_get(:@to_percent)).to eq(0.25)
    end

    it 'calculates correct percentages for middle partition' do
      partitioner = described_class.new(4, 2)

      expect(partitioner.instance_variable_get(:@from_percent)).to eq(0.25)
      expect(partitioner.instance_variable_get(:@to_percent)).to eq(0.5)
    end

    it 'calculates correct percentages for last partition' do
      partitioner = described_class.new(4, 4)

      expect(partitioner.instance_variable_get(:@from_percent)).to eq(0.75)
      expect(partitioner.instance_variable_get(:@to_percent)).to eq(1.0)
    end

    it 'handles single partition correctly' do
      partitioner = described_class.new(1, 1)

      expect(partitioner.instance_variable_get(:@from_percent)).to eq(0.0)
      expect(partitioner.instance_variable_get(:@to_percent)).to eq(1.0)
    end

    it 'uses floating point division for precise percentages' do
      partitioner = described_class.new(3, 1)

      from_percent = partitioner.instance_variable_get(:@from_percent)
      to_percent = partitioner.instance_variable_get(:@to_percent)

      expect(from_percent).to eq(0.0)
      expect(to_percent).to be_within(0.0001).of(0.3333333333333333)
    end
  end

  describe '#accept?' do
    let(:user_ids) { (1..1000).map { |i| "user_#{i}" } }

    context 'with 4 partitions' do
      let(:partition_count) { 4 }
      let(:partitioners) do
        (1..partition_count).map { |i| described_class.new(partition_count, i) }
      end

      it 'distributes users across all partitions' do
        partition_counts = partitioners.map do |partitioner|
          user_ids.count { |user_id| partitioner.accept?(user_id) }
        end

        # Each partition should get some users
        partition_counts.each do |count|
          expect(count).to be > 0
        end

        # Total should equal all users
        expect(partition_counts.sum).to eq(user_ids.length)
      end

      it 'ensures no user belongs to multiple partitions' do
        user_ids.each do |user_id|
          accepting_partitions = partitioners.count { |p| p.accept?(user_id) }
          expect(accepting_partitions).to eq(1), "User #{user_id} belongs to #{accepting_partitions} partitions"
        end
      end

      it 'maintains consistent assignment for same user_id' do
        user_id = 'consistent_user'

        # Test multiple times to ensure consistency
        results = 10.times.map do
          partitioners.map { |p| p.accept?(user_id) }
        end

        # All results should be identical
        results.each do |result|
          expect(result).to eq(results.first)
        end
      end
    end

    context 'with different partition counts' do
      it 'works with 2 partitions' do
        p1 = described_class.new(2, 1)
        p2 = described_class.new(2, 2)

        first_half = user_ids.count { |id| p1.accept?(id) }
        second_half = user_ids.count { |id| p2.accept?(id) }

        expect(first_half + second_half).to eq(user_ids.length)
        expect(first_half).to be > 0
        expect(second_half).to be > 0
      end

      it 'works with 10 partitions' do
        partitioners = (1..10).map { |i| described_class.new(10, i) }

        partition_counts = partitioners.map do |partitioner|
          user_ids.count { |user_id| partitioner.accept?(user_id) }
        end

        expect(partition_counts.sum).to eq(user_ids.length)
        partition_counts.each { |count| expect(count).to be > 0 }
      end

      it 'works with single partition' do
        partitioner = described_class.new(1, 1)

        accepted_count = user_ids.count { |id| partitioner.accept?(id) }

        expect(accepted_count).to eq(user_ids.length)
      end
    end
  end

  describe 'integration scenarios' do
    context 'real-world usage patterns' do
      let(:user_ids) { (1..10000).map { |i| "user_#{i}" } }

      it 'provides reasonable distribution across partitions' do
        partition_count = 5
        partitioners = (1..partition_count).map { |i| described_class.new(partition_count, i) }

        partition_counts = partitioners.map do |partitioner|
          user_ids.count { |user_id| partitioner.accept?(user_id) }
        end

        expected_per_partition = user_ids.length / partition_count

        partition_counts.each do |count|
          # Allow for some variation due to hashing, but should be reasonably close
          expect(count).to be_within(expected_per_partition * 0.2).of(expected_per_partition)
        end
      end

      it 'handles string and numeric user IDs consistently' do
        string_user_id = '12345'
        numeric_user_id = 12345

        partitioner = described_class.new(4, 1)

        string_result = partitioner.accept?(string_user_id)
        numeric_result = partitioner.accept?(numeric_user_id)

        expect(string_result).to eq(numeric_result)
      end

      it 'works with different user ID formats' do
        different_formats = [
          'user_123',
          'USER_123',
          '123',
          123,
          'uuid-1234-5678-9012',
          'email@example.com'
        ]

        partitioner = described_class.new(2, 1)

        different_formats.each do |user_id|
          result = partitioner.accept?(user_id)
          expect([true, false]).to include(result)
        end
      end
    end

    context 'boundary conditions' do
      it 'handles partition_id at boundaries' do
        # Test first partition
        first_partitioner = described_class.new(3, 1)
        expect(first_partitioner.instance_variable_get(:@from_percent)).to eq(0.0)

        # Test last partition
        last_partitioner = described_class.new(3, 3)
        expect(last_partitioner.instance_variable_get(:@to_percent)).to eq(1.0)
      end

      it 'ensures complete coverage with adjacent partitions' do
        user_ids = (1..100).map { |i| "user_#{i}" }

        # Test that adjacent partitions cover all users without overlap
        p1 = described_class.new(3, 1)
        p2 = described_class.new(3, 2)
        p3 = described_class.new(3, 3)

        user_ids.each do |user_id|
          accepted_by = [p1, p2, p3].count { |p| p.accept?(user_id) }
          expect(accepted_by).to eq(1), "User #{user_id} accepted by #{accepted_by} partitions"
        end
      end
    end
  end

  describe 'constants and configuration' do
    describe 'RAND_BASE' do
      it 'is set to correct value for 32-bit CRC' do
        expect(described_class::RAND_BASE).to eq(2**32 - 1)
        expect(described_class::RAND_BASE).to eq(4294967295)
      end

      it 'provides full range for CRC32 values' do
        # CRC32 returns values in range [0, 2^32 - 1]
        test_values = ['test1', 'test2', 'test3']

        test_values.each do |value|
          crc_value = Zlib.crc32(value)
          expect(crc_value).to be >= 0
          expect(crc_value).to be <= described_class::RAND_BASE
        end
      end
    end
  end

  describe 'error handling' do
    context 'with invalid parameters' do
      it 'handles zero partition_count by creating NaN and infinite percentages' do
        partitioner = described_class.new(0, 1)

        from_percent = partitioner.instance_variable_get(:@from_percent)
        to_percent = partitioner.instance_variable_get(:@to_percent)

        # (1-1)/0.0 = 0/0.0 = NaN, 1/0.0 = Infinity
        expect(from_percent).to be_nan
        expect(to_percent).to eq(Float::INFINITY)
      end

      it 'handles negative partition_id' do
        partitioner = described_class.new(4, -1)

        from_percent = partitioner.instance_variable_get(:@from_percent)
        to_percent = partitioner.instance_variable_get(:@to_percent)

        expect(from_percent).to eq(-0.5)
        expect(to_percent).to eq(-0.25)
      end

      it 'handles partition_id greater than partition_count' do
        partitioner = described_class.new(3, 5)

        from_percent = partitioner.instance_variable_get(:@from_percent)
        to_percent = partitioner.instance_variable_get(:@to_percent)

        expect(from_percent).to be > 1.0
        expect(to_percent).to be > 1.0
      end

      it 'handles nil user_id' do
        partitioner = described_class.new(2, 1)

        expect {
          partitioner.accept?(nil)
        }.not_to raise_error

        result = partitioner.accept?(nil)
        expect([true, false]).to include(result)
      end

      it 'handles empty string user_id' do
        partitioner = described_class.new(2, 1)

        result = partitioner.accept?('')
        expect([true, false]).to include(result)
      end
    end
  end

  describe 'performance characteristics' do
    it 'maintains consistent performance with different user_id lengths' do
      partitioner = described_class.new(4, 1)

      short_ids = (1..100).map { |i| i.to_s }
      long_ids = (1..100).map { |i| 'very_long_user_identifier_' + ('x' * 100) + i.to_s }

      # Both should complete without significant performance difference
      # This is more of a smoke test to ensure no obvious performance issues
      short_time = Benchmark.realtime do
        short_ids.each { |id| partitioner.accept?(id) }
      end

      long_time = Benchmark.realtime do
        long_ids.each { |id| partitioner.accept?(id) }
      end

      # Long IDs shouldn't be dramatically slower (CRC32 is quite fast)
      expect(long_time).to be < (short_time * 10)
    end
  end
end
