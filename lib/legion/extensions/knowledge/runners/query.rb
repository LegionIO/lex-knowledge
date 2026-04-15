# frozen_string_literal: true

require 'digest'

module Legion
  module Extensions
    module Knowledge
      module Runners
        module Query # rubocop:disable Legion/Extension/RunnerIncludeHelpers
          module_function

          def query(question:, top_k: nil, synthesize: true)
            started = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
            resolved_k = top_k || settings_top_k || 5

            chunks = retrieve_chunks(question, resolved_k)

            answer = (synthesize_answer(question, chunks) if synthesize && llm_available?)

            latency_ms = ((::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - started) * 1000).round

            score = average_score(chunks)
            unless chunks.empty?
              record_feedback(
                question:        question,
                chunk_ids:       chunks.filter_map { |c| c[:id] },
                retrieval_score: score.to_f,
                synthesized:     synthesize && llm_available?
              )
            end

            {
              success:  true,
              answer:   answer,
              sources:  chunks.map { |c| format_source(c) },
              metadata: build_metadata(chunks, score, latency_ms)
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
              metadata: build_metadata(chunks, average_score(chunks))
            }
          rescue StandardError => e
            { success: false, error: e.message }
          end

          def record_feedback(question:, chunk_ids:, retrieval_score:, synthesized: true, rating: nil)
            question_hash = ::Digest::SHA256.hexdigest(question.to_s)[0, 16]
            emit_feedback_event(
              question_hash:   question_hash,
              chunk_ids:       chunk_ids,
              retrieval_score: retrieval_score,
              synthesized:     synthesized,
              rating:          rating
            )
            { success: true, question_hash: question_hash, rating: rating }
          rescue StandardError => e
            { success: false, error: e.message }
          end

          def retrieve_chunks(question, top_k)
            return [] unless defined?(Legion::Extensions::Apollo)

            result = Legion::Extensions::Apollo::Runners::Knowledge.retrieve_relevant(
              query: question,
              limit: top_k,
              tags:  ['document_chunk']
            )
            result.is_a?(Hash) && result[:success] ? Array(result[:entries]) : []
          rescue StandardError => _e
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

            result = llm_chat(message: prompt, caller: { extension: 'lex-knowledge' })
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

          def build_metadata(chunks, score, latency_ms = nil)
            confidences = chunks.filter_map { |c| c[:confidence] }
            distances   = chunks.filter_map { |c| c[:distance] }
            source_names = chunks.filter_map do |c|
              c.dig(:metadata, :source_file) || c[:source_file]
            end.uniq
            statuses = chunks.group_by { |c| c[:status] }.transform_values(&:size)

            meta = {
              retrieval_score:   score,
              chunk_count:       chunks.size,
              confidence_avg:    confidences.empty? ? nil : (confidences.sum.to_f / confidences.size).round(4),
              confidence_range:  confidences.empty? ? nil : confidences.minmax,
              distance_range:    distances.empty?   ? nil : distances.minmax,
              source_files:      source_names,
              source_file_count: source_names.size,
              all_embedded:      chunks.none? { |c| zero_embedding?(c) },
              statuses:          statuses
            }
            meta[:latency_ms] = latency_ms unless latency_ms.nil?
            meta
          end
          private_class_method :build_metadata

          def zero_embedding?(chunk)
            emb = chunk[:embedding]
            return true if emb.nil?

            emb.is_a?(Array) && (emb.empty? || emb.all?(&:zero?))
          end
          private_class_method :zero_embedding?

          def emit_feedback_event(question_hash:, chunk_ids:, retrieval_score:, synthesized:, rating:)
            return unless defined?(Legion::Events)

            Legion::Events.emit('knowledge.query_feedback', {
                                  question_hash:   question_hash,
                                  chunk_ids:       chunk_ids,
                                  retrieval_score: retrieval_score,
                                  synthesized:     synthesized,
                                  rating:          rating
                                })
          rescue StandardError => _e
            nil
          end
          private_class_method :emit_feedback_event

          def llm_available?
            defined?(Legion::LLM)
          end
          private_class_method :llm_available?

          def settings_top_k
            return nil unless defined?(Legion::Settings)

            Legion::Settings.dig(:knowledge, :query, :top_k)
          rescue StandardError => _e
            nil
          end
          private_class_method :settings_top_k
        end
      end
    end
  end
end
