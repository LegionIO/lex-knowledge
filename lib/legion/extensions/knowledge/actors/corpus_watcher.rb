# frozen_string_literal: true

module Legion
  module Extensions
    module Knowledge
      module Actor
        class CorpusWatcher < Legion::Extensions::Actors::Every # rubocop:disable Legion/Extension/EveryActorRequiresTime
          include Legion::Logging::Helper
          include Legion::Settings::Helper

          def runner_class    = 'Legion::Extensions::Knowledge::Runners::Ingest'
          def runner_function = 'ingest_corpus'
          def check_subtask?  = false
          def generate_task?  = false

          def time
            settings[:actors][:watcher_interval]
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'knowledge.corpus_watcher.time')
            300
          end

          def enabled? # rubocop:disable Legion/Extension/ActorEnabledSideEffects
            resolve_monitors.any?
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'knowledge.corpus_watcher.enabled')
            false
          end

          def args
            { monitors: resolve_monitors }
          end

          private

          def resolve_monitors
            Runners::Monitor.resolve_monitors
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'knowledge.corpus_watcher.resolve_monitors')
            []
          end
        end
      end
    end
  end
end
