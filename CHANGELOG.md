# Changelog

## 0.1.0

First release as a gem, extracted from `judgeme:lib/event_worker` with its git history. judgeme keeps its behaviour by setting `field_types` and `liveness_file` in its initializer.

### Added

- `field_types` setting: which fields a writer casts to `:integer` or `:json` when reading a stream back. Defaults to `{}`. It replaces the hardcoded `id`, `shop_id`, `review_id` and `data` casting.
- `liveness_file` setting: the file workers touch on every fetch. Defaults to `nil`, which touches nothing. It replaces the hardcoded `/tmp/liveness`.

### Changed

- `require 'event_worker'` loads without Rails. Runtime dependencies are `activesupport` (>= 7.1), `benchmark`, `bigdecimal` and `logger`. There is no `redis` dependency: the app injects its client, and redis-rb 4.5 and 5.4 both work.
- `event_worker/testing` is opt-in. Require it after RSpec; it no longer depends on `RAILS_ENV`.

### Fixed

- Abstract reader and writer methods raise `NotImplementedError` instead of a `NameError` for `NotImplemented`.
- `flush(trim_messages_older:)` trims instead of raising `ArgumentError`. `StreamWriters::Base#flush` and the fake-mode writer forward keyword arguments to `write`.
- `Testing.reset` deletes with a generic `DEL`, so it works on a pool of bare `RedisClient`s, and sends nothing when no topic was written.
- `RedisLock#refresh` with `use_lua: true` refreshes the lock. It raised on Redis 7 and on redis-rb 5, and returned `false` even when the refresh succeeded.
