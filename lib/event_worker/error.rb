# frozen_string_literal: true

module EventWorker
  class Error < StandardError
    class ExitSignal < Error; end
  end
end
