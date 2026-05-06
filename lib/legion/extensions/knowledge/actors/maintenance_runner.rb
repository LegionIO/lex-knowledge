# frozen_string_literal: true

module Legion
  module Extensions
    module Knowledge
      module Actor
        class MaintenanceRunner < Legion::Extensions::Actors::Every # rubocop:disable Legion/Extension/EveryActorRequiresTime
          include Legion::Logging::Helper
          include Legion::Settings::Helper

          def runner_class    = 'Legion::Extensions::Knowledge::Runners::Maintenance'
          def runner_function = 'health'
          def check_subtask?  = false
          def generate_task?  = false

          def time
            settings[:actors][:maintenance_interval]
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'knowledge.maintenance_runner.time')
            21_600
          end

          def enabled? # rubocop:disable Legion/Extension/ActorEnabledSideEffects
            return false unless corpus_path && !corpus_path.empty?

            true
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'knowledge.maintenance_runner.enabled')
            false
          end

          def args
            { path: corpus_path }
          end

          private

          def corpus_path
            settings[:corpus_path]
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'knowledge.maintenance_runner.corpus_path')
            nil
          end
        end
      end
    end
  end
end
