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

          def enabled?
            defined?(Legion::Transport) &&
              defined?(Legion::Extensions::Knowledge::Runners::Ingest)
          rescue StandardError
            false
          end
        end
      end
    end
  end
end
