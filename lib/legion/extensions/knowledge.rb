# frozen_string_literal: true

require_relative 'knowledge/version'
require_relative 'knowledge/helpers/manifest'
require_relative 'knowledge/helpers/manifest_store'
require_relative 'knowledge/helpers/parser'
require_relative 'knowledge/helpers/chunker'
require_relative 'knowledge/runners/ingest'
require_relative 'knowledge/runners/query'
require_relative 'knowledge/runners/corpus'
require_relative 'knowledge/runners/maintenance'
require_relative 'knowledge/client'

if defined?(Legion::Transport)
  require_relative 'knowledge/transport/exchanges/knowledge'
  require_relative 'knowledge/transport/queues/ingest'
  require_relative 'knowledge/transport/messages/ingest_message'
end

require_relative 'knowledge/actors/corpus_watcher' if defined?(Legion::Extensions::Actors::Every)

require_relative 'knowledge/actors/corpus_ingest' if defined?(Legion::Extensions::Actors::Subscription)

module Legion
  module Extensions
    module Knowledge
      extend Legion::Extensions::Core if defined?(Legion::Extensions::Core)
    end
  end
end
