# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EventWorker::StreamWriters::Base do
  subject(:writer) { described_class.new(double('stream client'), '#event_worker_spec') }

  it 'raises NotImplementedError from each abstract method', :aggregate_failures do
    %i[size first last all each write trim].each do |abstract_method|
      expect { writer.public_send(abstract_method) }.to raise_error(NotImplementedError)
    end
  end
end
