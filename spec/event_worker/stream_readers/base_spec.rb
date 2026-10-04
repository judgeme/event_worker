# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EventWorker::StreamReaders::Base do
  subject(:reader) { described_class.new(double('stream client'), offsets: {}) }

  it 'raises NotImplementedError from each abstract method', :aggregate_failures do
    expect { reader.fetch(['#event_worker_spec']) }.to raise_error(NotImplementedError)
    expect { reader.each_entry_with_topic([]) }.to raise_error(NotImplementedError)
  end
end
