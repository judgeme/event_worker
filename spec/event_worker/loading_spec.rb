# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'open3'
require 'rbconfig'

# A separate process, because this one has already loaded RSpec, the spec_helper and its Redis gems.
RSpec.describe "require 'event_worker'" do
  subject(:loaded) do
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-I', lib_dir, '-e', script, lib_dir)
    expect(status).to be_success, "plain Ruby could not load the gem:\n#{stderr}"
    JSON.parse(stdout, symbolize_names: true)
  end

  let(:lib_dir) { File.realpath('../../lib', __dir__) }
  let(:script) do
    <<~'RUBY'
      require 'event_worker'
      require 'json'

      lib_prefix = "#{ARGV.fetch(0)}/"
      constants = [EventWorker::Worker::V2, EventWorker::Utils::RedisLock, EventWorker::StreamReaders::PgRecords]
      files = $LOADED_FEATURES.select { |path| path.start_with?(lib_prefix) }

      puts JSON.generate(
        rails: defined?(Rails),
        testing: defined?(EventWorker::Testing),
        constants: constants.map(&:name),
        files: files.map { |path| path.delete_prefix(lib_prefix) }
      )
    RUBY
  end

  it 'loads every library file in plain Ruby, with Rails and the testing support absent', :aggregate_failures do
    library_files = Dir.glob('**/*.rb', base: lib_dir) - ['event_worker/testing.rb']

    expect(loaded).to include(
      rails: nil,
      testing: nil,
      constants: %w[EventWorker::Worker::V2 EventWorker::Utils::RedisLock EventWorker::StreamReaders::PgRecords]
    )
    expect(loaded[:files]).to match_array(library_files)
  end
end
