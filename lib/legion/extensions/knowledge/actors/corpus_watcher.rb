# frozen_string_literal: true

module Legion
  module Extensions
    module Knowledge
      module Actor
        class CorpusWatcher < Legion::Extensions::Actors::Every
          def runner_class    = 'Legion::Extensions::Knowledge::Runners::Ingest'
          def runner_function = 'ingest_corpus'
          def check_subtask?  = false
          def generate_task?  = false

          def every_interval
            if defined?(Legion::Settings) && !Legion::Settings[:knowledge].nil?
              Legion::Settings.dig(:knowledge, :actors, :watcher_interval) || 300
            else
              300
            end
          rescue StandardError
            300
          end

          def enabled?
            corpus_path && !corpus_path.empty?
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
