module EventWorker
  module Utils
    class Time
      class << self
        def tick_time(resolution, time, time_offset: 0, offset: 1)
          i = (time.to_f - time_offset) / resolution
          ::Time.at((i.to_i + offset) * resolution + time_offset)
        end
      end
    end
  end
end
