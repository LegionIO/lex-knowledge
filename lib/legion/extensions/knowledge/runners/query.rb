# frozen_string_literal: true

module Legion
  module Extensions
    module Knowledge
      module Runners
        module Query
          module_function

          def query(question:, top_k: nil, synthesize: true)
            started = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
            resolved_k = top_k || settings_top_k || 5

            chunks = retrieve_chunks(question, resolved_k)

            answer = (synthesize_answer(question, chunks) if synthesize && llm_available?)

            latency_ms = ((::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - started) * 1000).round

            {
              success:  true,
              answer:   answer,
              sources:  chunks.map { |c| format_source(c) },
              metadata: {
                retrieval_score: average_score(chunks),
                chunk_count:     chunks.size,
                latency_ms:      latency_ms
              }
            }
          rescue StandardError => e
            { success: false, error: e.message }
          end

          def retrieve(question:, top_k: nil)
            resolved_k = top_k || settings_top_k || 5
            chunks     = retrieve_chunks(question, resolved_k)

            {
              success:  true,
              sources:  chunks.map { |c| format_source(c) },
              metadata: {
                chunk_count: chunks.size
              }
            }
          rescue StandardError => e
            { success: false, error: e.message }
          end

          def retrieve_chunks(question, top_k)
            return [] unless defined?(Legion::Extensions::Apollo)

            Legion::Extensions::Apollo::Runners::Knowledge.retrieve_relevant(
              query: question,
              limit: top_k,
              tags:  ['document_chunk']
            )
          rescue StandardError
            []
          end
          private_class_method :retrieve_chunks

          def synthesize_answer(question, chunks)
            return nil unless llm_available?

            context_text = chunks.map { |c| c[:content] }.join("\n\n---\n\n")
            prompt = if context_text.empty?
                       question
                     else
                       "You are a helpful assistant. Use the context below to answer the question.\n\n" \
                         "Context:\n#{context_text}\n\nQuestion: #{question}\n\nAnswer:"
                     end

            result = Legion::LLM.chat(message: prompt, caller: { extension: 'lex-knowledge' })
            result.is_a?(Hash) ? result[:content] : result
          rescue StandardError => e
            "Error generating answer: #{e.message}"
          end
          private_class_method :synthesize_answer

          def format_source(chunk)
            {
              content:     chunk[:content],
              source_file: chunk.dig(:metadata, :source_file) || chunk[:source_file],
              heading:     chunk.dig(:metadata, :heading)     || chunk[:heading],
              distance:    chunk[:distance] || chunk[:score]
            }
          end
          private_class_method :format_source

          def average_score(chunks)
            return nil if chunks.empty?

            scores = chunks.filter_map { |c| c[:distance] || c[:score] }
            return nil if scores.empty?

            (scores.sum.to_f / scores.size).round(4)
          end
          private_class_method :average_score

          def llm_available?
            defined?(Legion::LLM)
          end
          private_class_method :llm_available?

          def settings_top_k
            return nil unless defined?(Legion::Settings)

            Legion::Settings.dig(:knowledge, :query, :top_k)
          rescue StandardError
            nil
          end
          private_class_method :settings_top_k
        end
      end
    end
  end
end
