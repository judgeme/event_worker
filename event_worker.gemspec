# frozen_string_literal: true

require_relative 'lib/event_worker/version'

Gem::Specification.new do |s|
  s.name = 'event_worker'
  s.version = EventWorker::VERSION
  s.summary = 'Event Worker'
  s.authors = ['Khoi Vu']
  s.files = Dir['lib/**/*.rb']
  s.required_ruby_version = '>= 3.2'

  s.add_dependency 'activesupport', '>= 7.1'
  s.add_dependency 'benchmark'
  s.add_dependency 'bigdecimal'
  s.add_dependency 'logger'
end
