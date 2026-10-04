# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EventWorker::Utils::RedisLock do
  let(:key) { "event_worker_spec:lock:#{SecureRandom.hex(8)}" }

  describe '#refresh' do
    subject(:result) { lock.refresh }
    let(:lock) { described_class.acquire_one_of!(2, redis, key) }

    after { redis.del("#{key}:1") }

    it { is_expected.to eq(true) }

    context 'when the lock token is not valid' do
      before { redis.set(lock.key, 'invalid_token') }
      it { is_expected.to eq(false) }
    end

    context 'when token is expired' do
      before { redis.expire(lock.key, -1) }
      it { is_expected.to eq(false) }

      context 'when strict is false' do
        subject(:result) { lock.refresh(strict: false) }
        it { is_expected.to eq(true) }
      end
    end
  end

  context 'integration tests' do
    after { redis.del("#{key}:1", "#{key}:2") }

    it 'works' do
      lock1 = described_class.acquire_one_of!(2, redis, key)
      lock2 = described_class.acquire_one_of!(2, redis, key)
      expect { described_class.acquire_one_of!(2, redis, key) }.to raise_error(RuntimeError)
      expect(lock1).to be_a(EventWorker::Utils::RedisLock)
      expect(lock2).to be_a(EventWorker::Utils::RedisLock)
      expect(lock1.index).to eq(1)
      expect(lock2.index).to eq(2)
      expect(lock1.key).to eq("#{key}:1")
      expect(lock2.key).to eq("#{key}:2")
      expect(lock1.valid?).to eq(true)
      expect(lock2.valid?).to eq(true)
      expect(lock1.ttl).to be_within(1.second).of(1.minutes)
      expect(lock2.ttl).to be_within(1.second).of(1.minutes)

      expect(lock1.refresh).to eq(true)
      expect(lock1.release).to eq(true)
      expect(lock1.release).to eq(false)
      expect(lock1.refresh).to eq(false)
      expect(lock1.ttl).to eq(-2)
      expect(lock2.ttl).to be_within(1.second).of(1.minutes)
    end
  end

  [false, true].each do |use_lua|
    context "with use_lua: #{use_lua} on a real Redis" do
      let(:key) { "event_worker_spec:lock:#{SecureRandom.hex(8)}" }
      let(:lock) { described_class.acquire_one_of!(1, redis, key, use_lua:) }

      after { redis.del("#{key}:1") }

      it 'refreshes a held lock back to the full minute', :aggregate_failures do
        redis.expire(lock.key, 5)

        expect(lock.refresh).to be(true)
        expect(lock.ttl).to be_within(1).of(60)
      end

      it 'does not refresh a lock another holder has taken', :aggregate_failures do
        redis.set(lock.key, 'another holder')

        expect(lock.refresh).to be(false)
        expect(redis.get(lock.key)).to eq('another holder')
      end

      it 'releases a held lock', :aggregate_failures do
        expect(lock.release).to be(true)
        expect(redis.exists?(lock.key)).to be(false)
      end

      it 'does not release a lock another holder has taken', :aggregate_failures do
        redis.set(lock.key, 'another holder')

        expect(lock.release).to be(false)
        expect(redis.get(lock.key)).to eq('another holder')
      end
    end
  end
end
