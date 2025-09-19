require 'rails_helper'

RSpec.describe EventWorker::Utils::RedisLock do
  let(:key) { Faker::Alphanumeric.alphanumeric(number: 10) }

  describe '#refresh' do
    subject(:result) { lock.refresh }
    let(:lock) { described_class.acquire_one_of!(2, $redis, key) }

    it { is_expected.to eq(true) }

    context 'when the lock token is not valid' do
      before { $redis.set(lock.key, 'invalid_token') }
      it { is_expected.to eq(false) }
    end

    context 'when token is expired' do
      before { $redis.expire(lock.key, -1) }
      it { is_expected.to eq(true) }
    end
  end

  context 'integration tests' do
    it 'works' do
      lock1 = described_class.acquire_one_of!(2, $redis, 'key')
      lock2 = described_class.acquire_one_of!(2, $redis, 'key')
      expect { described_class.acquire_one_of!(2, $redis, 'key') }.to raise_error(RuntimeError)
      expect(lock1).to be_a(EventWorker::Utils::RedisLock)
      expect(lock2).to be_a(EventWorker::Utils::RedisLock)
      expect(lock1.index).to eq(1)
      expect(lock2.index).to eq(2)
      expect(lock1.key).to eq("key:1")
      expect(lock2.key).to eq("key:2")
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
end
