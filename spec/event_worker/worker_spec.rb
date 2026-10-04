# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe EventWorker::Worker do
  subject(:worker) { worker_class.new }

  let(:worker_class) do
    reader = double('stream reader', fetch_new: nil)

    Class.new do
      include EventWorker::Worker

      define_method(:stream_reader) { reader }

      def topics = []

      def restore_last_state; end

      def logger = Logger.new(nil)
    end
  end

  around do |example|
    original_config = EventWorker.config
    example.run
  ensure
    EventWorker.config = original_config
  end

  describe '#process_new_events' do
    context 'when liveness_file is set' do
      let(:liveness_file) { File.join(Dir.tmpdir, "event_worker_liveness_#{SecureRandom.hex(8)}") }

      before { EventWorker.configure { |config| config.liveness_file = liveness_file } }

      after { FileUtils.rm_f(liveness_file) }

      it 'touches it' do
        expect { worker.process_new_events }.to change { File.exist?(liveness_file) }.from(false).to(true)
      end
    end

    context 'when liveness_file is not set' do
      before { EventWorker.config = EventWorker::Configuration.new }

      it 'touches no file' do
        expect(FileUtils).not_to receive(:touch)

        worker.process_new_events
      end
    end
  end
end
