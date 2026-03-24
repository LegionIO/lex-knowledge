# frozen_string_literal: true

require_relative 'knowledge/version'
require_relative 'knowledge/helpers/manifest'
require_relative 'knowledge/helpers/parser'
require_relative 'knowledge/helpers/chunker'
require_relative 'knowledge/runners/ingest'
require_relative 'knowledge/runners/query'
require_relative 'knowledge/runners/corpus'
require_relative 'knowledge/client'

module Legion
  module Extensions
    module Knowledge
      extend Legion::Extensions::Core if defined?(Legion::Extensions::Core)
    end
  end
end
