# frozen_string_literal: true

module Legion
  module Extensions
    module Knowledge
      module Actor
        class CorpusIngest < Legion::Extensions::Actors::Subscription
          include Legion::Logging::Helper
          include Legion::Settings::Helper

          def runner_class    = 'Legion::Extensions::Knowledge::Runners::Ingest'
          def runner_function = 'ingest_file'
          def check_subtask?  = false
          def generate_task?  = false

          def enabled? # rubocop:disable Legion/Extension/ActorEnabledSideEffects
            Legion.const_defined?(:Transport, false) &&
              defined?(Legion::Extensions::Knowledge::Runners::Ingest)
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'knowledge.corpus_ingest.enabled')
            false
          end
        end
      end
    end
  end
end
