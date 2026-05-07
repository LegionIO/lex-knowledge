# frozen_string_literal: true

module Legion
  module Extensions
    module Knowledge
      module Actor
        class MaintenanceRunner < Legion::Extensions::Actors::Every # rubocop:disable Legion/Extension/EveryActorRequiresTime
          def runner_class    = 'Legion::Extensions::Knowledge::Runners::Maintenance'
          def runner_function = 'health'
          def check_subtask?  = false
          def generate_task?  = false

          def time
            if defined?(Legion::Settings) && !Legion::Settings[:knowledge].nil?
              Legion::Settings.dig(:knowledge, :actors, :maintenance_interval) || 21_600
            else
              21_600
            end
          rescue StandardError => e
            log.warn(e.message)
            21_600
          end

          def enabled? # rubocop:disable Legion/Extension/ActorEnabledSideEffects
            return true if corpus_path && !corpus_path.empty?

            Runners::Monitor.resolve_monitors.any?
          rescue StandardError => e
            log.warn(e.message)
            false
          end

          def args
            path = corpus_path
            return { path: path } if path && !path.empty?

            monitors = Runners::Monitor.resolve_monitors
            monitors.any? ? { path: monitors.first[:path] } : { path: nil }
          end

          private

          def log
            Legion::Logging
          end

          def corpus_path
            return nil unless defined?(Legion::Settings) && !Legion::Settings[:knowledge].nil?

            Legion::Settings.dig(:knowledge, :corpus_path)
          rescue StandardError => e
            log.warn(e.message)
            nil
          end
        end
      end
    end
  end
end
