# frozen_string_literal: true

require 'legion/logging'
require 'legion/settings'
require 'legion/json'
require_relative 'knowledge/version'
require_relative 'knowledge/helpers/manifest'
require_relative 'knowledge/helpers/manifest_store'
require_relative 'knowledge/helpers/parser'
require_relative 'knowledge/helpers/chunker'
require_relative 'knowledge/helpers/apollo_models'
require_relative 'knowledge/runners/ingest'
require_relative 'knowledge/runners/query'
require_relative 'knowledge/runners/corpus'
require_relative 'knowledge/runners/maintenance'
require_relative 'knowledge/runners/monitor'
require_relative 'knowledge/client'

if Legion.const_defined?(:Transport, false)
  require_relative 'knowledge/transport/exchanges/knowledge'
  require_relative 'knowledge/transport/queues/ingest'
  require_relative 'knowledge/transport/messages/ingest_message'
  require_relative 'knowledge/transport/messages/monitor_reload'
end

require_relative 'knowledge/actors/corpus_watcher'
require_relative 'knowledge/actors/maintenance_runner'

require_relative 'knowledge/actors/corpus_ingest'

module Legion
  module Extensions
    module Knowledge
      extend Legion::Logging::Helper
      extend Legion::Settings::Helper
      extend Legion::Extensions::Core if defined?(Legion::Extensions::Core)

      def self.remote_invocable?
        false
      end

      def self.default_settings
        {
          corpus_path: nil,
          monitors:    [],
          chunker:     {
            max_tokens:     512,
            overlap_tokens: 128
          },
          query:       {
            top_k:           5,
            neighbor_radius: 1
          },
          ingest:      {
            filter_prompt:    nil,
            filter_threshold: 0.5
          },
          maintenance: {
            stale_threshold:      0.3,
            cold_chunk_days:      7,
            quality_report_limit: 10
          },
          actors:      {
            watcher_interval:     300,
            maintenance_interval: 21_600
          }
        }
      end
    end
  end
end
