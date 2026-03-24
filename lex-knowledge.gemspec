# frozen_string_literal: true

require_relative 'lib/legion/extensions/knowledge/version'

Gem::Specification.new do |spec|
  spec.name          = 'lex-knowledge'
  spec.version       = Legion::Extensions::Knowledge::VERSION
  spec.authors       = ['Matthew Iverson']
  spec.email         = ['matt@iverson.io']

  spec.summary       = 'Document corpus ingestion and knowledge query pipeline for LegionIO'
  spec.description   = 'Document corpus ingestion and knowledge query pipeline for LegionIO'
  spec.homepage      = 'https://github.com/LegionIO/lex-knowledge'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 3.4'

  spec.files         = Dir['lib/**/*', 'LICENSE', 'README.md']
  spec.require_paths = ['lib']
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.add_dependency 'legion-cache',     '>= 1.3.13'
  spec.add_dependency 'legion-crypt',     '>= 1.4.9'
  spec.add_dependency 'legion-data',      '>= 1.5.0'
  spec.add_dependency 'legion-json',      '>= 1.2.1'
  spec.add_dependency 'legion-logging',   '>= 1.3.3'
  spec.add_dependency 'legion-settings',  '>= 1.3.15'
  spec.add_dependency 'legion-transport', '>= 1.3.11'
end
