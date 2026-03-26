# frozen_string_literal: true

module Legion
  module Extensions
    module Knowledge
      module Actor
        class MaintenanceRunner < Legion::Extensions::Actors::Every
          def runner_class    = 'Legion::Extensions::Knowledge::Runners::Maintenance'
          def runner_function = 'health'
          def check_subtask?  = false
          def generate_task?  = false

          def every_interval
            if defined?(Legion::Settings) && !Legion::Settings[:knowledge].nil?
              Legion::Settings.dig(:knowledge, :actors, :maintenance_interval) || 21_600
            else
              21_600
            end
          rescue StandardError
            21_600
          end

          def enabled?
            return false unless corpus_path && !corpus_path.empty?

            true
          rescue StandardError
            false
          end

          def args
            { path: corpus_path }
          end

          private

          def corpus_path
            return nil unless defined?(Legion::Settings) && !Legion::Settings[:knowledge].nil?

            Legion::Settings.dig(:knowledge, :corpus_path)
          rescue StandardError
            nil
          end
        end
      end
    end
  end
end
