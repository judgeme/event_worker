# event_worker

Redis Streams producers and consumers for Judge.me's Rails apps. A stream class appends messages to a topic (`XADD`), and a worker reads the topics it follows (`XREAD`), handles each event and saves its offsets. Both `judgeme` and `emails` bundle it from this repo.

## Install

```ruby
gem 'event_worker', git: 'https://github.com/judgeme/event_worker.git', tag: 'v0.1.0'
```

## Configure

In an initializer:

```ruby
EventWorker.configure do |config|
  config.stream_store = :redis_stream, STREAM_REDIS
  config.field_types = { 'id' => :integer, 'shop_id' => :integer, 'data' => :json }
  config.liveness_file = '/tmp/liveness'
end

EventWorker::Context.logger = Rails.logger
```

- `stream_store`: `:redis_stream` and the stream client, an object that yields a connection from `#with` (a `ConnectionPool`).
- `field_types`: how a writer casts fields when reading a stream back (`first`, `last`, `all`, `each`). `:integer` or `:json`; unlisted fields stay strings. Defaults to `{}`. Readers never cast.
- `liveness_file`: a path workers touch on every fetch, for a container health check. Defaults to `nil`, which touches nothing.
- `EventWorker::Context.logger`: where `Worker::V2` logs its timings. Defaults to `STDOUT`; `nil` silences it.

`judgeme:config/initializers/redis_event_worker.rb` is a working example.

## Use

A stream:

```ruby
class OrderEvent
  include EventWorker::Stream::Message

  self.topic = '#orders'
end

OrderEvent.push({ id: order.id, status: 'paid' })

writer = OrderEvent.stream_writer
writer << { id: order.id, status: 'paid' }
writer.flush(trim_messages_older: EventWorker::Utils::Offset.time_to_offset(1.hour.ago))
```

Redis stores strings, so a consumer reads `id` back as `"123"`. `trim_messages_older` trims in the same `XADD` (`MINID`).

A worker includes `EventWorker::Worker::V2` and defines `topics`, `restore_last_state(context)`, `handle(context, event)`, `save(context)` and `stream_reader`, then calls `run`. Each event is a hash of the stored fields plus `_topic` and `_id`. V2 fetches, handles and saves on separate threads, so memoize `stream_reader`: one rebuilt from the handled offsets fetches the in-flight batch again.

## Redis clients

The gem declares no `redis` dependency. The app injects the client, and the gem works with redis-rb 4.5 (`judgeme`) and 5.4 (`emails`), plus a `ConnectionPool` of bare `RedisClient`s.

- `EventWorker::Utils::RedisLock` calls redis-rb's own methods (`set(nx:, ex:)`, `eval`, `ttl`), so give it a plain redis-rb client, not a pool or a `RedisClient`.
- **Read timeout.** The reader sends `XREAD … BLOCK block_msec` as a generic command, so the client adds no padding to its read timeout. Keep `block_msec` (default 2000) below the client's `read_timeout`, which is 1 s by default on redis-rb 5. Otherwise every idle read times out. Pass `block_msec:` to `StreamReaders::RedisStream.new`, or raise the client's `read_timeout`.

## Testing

Test support is opt-in. Require it after RSpec, in a support file:

```ruby
require 'event_worker/testing'

RSpec.configure do |config|
  config.before(:suite) { EventWorker::Testing.fake! }
  config.after { EventWorker::Testing.reset }
  config.include EventWorker::Testing::Matchers
end
```

- `fake!` keeps written messages in memory. Writers fake `write`, `size`, `first`, `last` and `all`; `trim` and readers always hit Redis.
- `real!` writes to Redis as well, for specs that read the stream back.
- `reset` clears the faked messages and, in real mode, deletes the topics written since the last reset.
- Matchers: `expect(OrderEvent).to push_event(id: 1, status: 'paid')`, and `an_event_id` / `be_an_event_id`.

The mode is global, so a spec that switches to `real!` switches back to `fake!` in an `ensure`.

## Development

The specs need a Redis at `REDIS_URL`, by default `redis://localhost:6379/15`. They never flush it: each spec writes its own random keys and deletes them.

CI runs two legs, one per app's Redis stack: judgeme's redis-rb 4.5 with connection_pool 2.5, and emails' redis-rb 5.4 with connection_pool 3.0. Run both before a release:

```sh
(export REDIS_GEM_VERSION='~> 4.5.0' CONNECTION_POOL_GEM_VERSION='~> 2.5'; rm -f Gemfile.lock && bundle install && bundle exec rspec)
(export REDIS_GEM_VERSION='~> 5.4' CONNECTION_POOL_GEM_VERSION='~> 3.0'; rm -f Gemfile.lock && bundle install && bundle exec rspec)
```

`Gemfile.lock` is not committed, because the two legs resolve different redis versions.

To try a change in an app, point its Gemfile at `path:` temporarily and don't commit it. Bundler's `local.` override refuses a `tag:`-only source.

## Releasing

1. Bump `EventWorker::VERSION` in `lib/event_worker/version.rb`.
2. Add a `CHANGELOG.md` entry.
3. Merge to `main`, then tag it `vX.Y.Z` and push the tag.
4. Update the `tag:` in both apps' Gemfiles (`judgeme:Gemfile`, `emails:Gemfile`) and run `bundle update event_worker --conservative` in each.
