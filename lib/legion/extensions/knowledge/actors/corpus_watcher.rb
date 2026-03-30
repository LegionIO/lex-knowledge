# frozen_string_literal: true

module Legion
  module Extensions
    module Knowledge
      module Actor
        class CorpusWatcher < Legion::Extensions::Actors::Every # rubocop:disable Legion/Extension/EveryActorRequiresTime
          def runner_class    = 'Legion::Extensions::Knowledge::Runners::Ingest'
          def runner_function = 'ingest_corpus'
          def check_subtask?  = false
          def generate_task?  = false

          def time
            if defined?(Legion::Settings) && !Legion::Settings[:knowledge].nil?
              Legion::Settings.dig(:knowledge, :actors, :watcher_interval) || 300
            else
              300
            end
          rescue StandardError => e
            log.warn(e.message)
            300
          end

          def enabled? # rubocop:disable Legion/Extension/ActorEnabledSideEffects
            resolve_monitors.any?
          rescue StandardError => e
            log.warn(e.message)
            false
          end

          def args
            { monitors: resolve_monitors }
          end

          private

          def log
            Legion::Logging
          end

          def resolve_monitors
            Runners::Monitor.resolve_monitors
          rescue StandardError => e
            log.warn(e.message)
            []
          end
        end
      end
    end
  end
end
