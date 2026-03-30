# frozen_string_literal: true

module Legion
  module Extensions
    module Knowledge
      module Actor
        class CorpusIngest < Legion::Extensions::Actors::Subscription
          def runner_class    = 'Legion::Extensions::Knowledge::Runners::Ingest'
          def runner_function = 'ingest_file'
          def check_subtask?  = false
          def generate_task?  = false

          def enabled? # rubocop:disable Legion/Extension/ActorEnabledSideEffects
            Legion.const_defined?(:Transport, false) &&
              defined?(Legion::Extensions::Knowledge::Runners::Ingest)
          rescue StandardError => _e
            false
          end
        end
      end
    end
  end
end
