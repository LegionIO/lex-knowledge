# frozen_string_literal: true

require_relative '../helpers/apollo_models'

require 'digest'

module Legion
  module Extensions
    module Knowledge
      module Runners
        module Query # rubocop:disable Legion/Extension/RunnerIncludeHelpers
          extend Legion::Logging::Helper
          extend Legion::JSON::Helper
          extend Legion::Settings::Helper

          module_function

          def query(question:, top_k: nil, synthesize: true, expand_neighbors: false, neighbor_radius: nil)
            started = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
            resolved_k      = top_k || settings[:query][:top_k]
            resolved_radius = resolve_neighbor_radius(neighbor_radius)

            chunks = retrieve_chunks(
              question,
              resolved_k,
              expand_neighbors: expand_neighbors,
              neighbor_radius:  resolved_radius
            )

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
            handle_exception(e, level: :warn, operation: 'knowledge.query.query')
            { success: false, error: e.message }
          end

          def retrieve(question:, top_k: nil, expand_neighbors: false, neighbor_radius: nil)
            resolved_k      = top_k || settings[:query][:top_k]
            resolved_radius = resolve_neighbor_radius(neighbor_radius)
            chunks          = retrieve_chunks(
              question,
              resolved_k,
              expand_neighbors: expand_neighbors,
              neighbor_radius:  resolved_radius
            )

            {
              success:  true,
              sources:  chunks.map { |c| format_source(c) },
              metadata: build_metadata(chunks, average_score(chunks))
            }
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'knowledge.query.retrieve')
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
            handle_exception(e, level: :warn, operation: 'knowledge.query.record_feedback')
            { success: false, error: e.message }
          end

          def retrieve_chunks(question, top_k, expand_neighbors: false, neighbor_radius: 1)
            return [] unless defined?(Legion::Extensions::Apollo)

            result = Legion::Extensions::Apollo::Runners::Knowledge.retrieve_relevant(
              query: question,
              limit: top_k,
              tags:  ['document_chunk']
            )
            chunks = result.is_a?(Hash) && result[:success] ? Array(result[:entries]) : []
            expand_neighbors ? expand_neighbor_chunks(chunks, neighbor_radius) : chunks
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'knowledge.query.retrieve_chunks')
            []
          end
          private_class_method :retrieve_chunks

          def expand_neighbor_chunks(chunks, neighbor_radius)
            return chunks if chunks.empty?

            radius = neighbor_radius.to_i
            return chunks unless radius.positive? && Helpers::ApolloModels.entry_available?

            merge_neighbor_chunks(chunks.flat_map { |chunk| neighbor_window_for(chunk, radius) })
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'knowledge.query.expand_neighbor_chunks')
            chunks
          end
          private_class_method :expand_neighbor_chunks

          def neighbor_window_for(chunk, radius)
            context = chunk_context(chunk)
            return [chunk] unless context[:source_file] && !context[:chunk_index].nil?

            source_file = context[:source_file]
            chunk_index = context[:chunk_index].to_i
            lower       = chunk_index - radius
            upper       = chunk_index + radius

            rows = neighbor_dataset(source_file, lower, upper).all.map { |entry| chunk_from_entry(entry) }
            rows << chunk unless rows.any? { |row| chunk_dedupe_key(row) == chunk_dedupe_key(chunk) }
            rows.sort_by { |row| chunk_context(row)[:chunk_index].to_i }
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'knowledge.query.neighbor_window')
            [chunk]
          end
          private_class_method :neighbor_window_for

          def neighbor_dataset(source_file, lower, upper)
            Helpers::ApolloModels.entry
                                 .where(content_type: 'document_chunk')
                                 .where(Sequel.lit("source_context->>'source_file' = ?", source_file))
                                 .where(Sequel.lit("(source_context->>'chunk_index')::integer BETWEEN ? AND ?", lower, upper))
                                 .order(Sequel.lit("(source_context->>'chunk_index')::integer ASC"))
          end
          private_class_method :neighbor_dataset

          def chunk_from_entry(entry)
            values = entry.respond_to?(:values) ? entry.values : entry
            context = normalize_context(values[:source_context] || values[:metadata] || values[:context])

            {
              id:               values[:id],
              content:          values[:content],
              content_type:     values[:content_type],
              confidence:       values[:confidence],
              tags:             values[:tags],
              source_agent:     values[:source_agent],
              knowledge_domain: values[:knowledge_domain],
              status:           values[:status],
              content_hash:     values[:content_hash],
              metadata:         context
            }.compact
          end
          private_class_method :chunk_from_entry

          def merge_neighbor_chunks(chunks)
            chunks.each_with_object({}) do |chunk, merged|
              key = chunk_dedupe_key(chunk)
              merged[key] ||= chunk
            end.values
          end
          private_class_method :merge_neighbor_chunks

          def synthesize_answer(question, chunks)
            return nil unless llm_available?

            context_text = chunks.map { |c| c[:content] }.join("\n\n---\n\n")
            prompt = if context_text.empty?
                       question
                     else
                       "You are a helpful assistant. Use the context below to answer the question.\n\n" \
                         "Context:\n#{context_text}\n\nQuestion: #{question}\n\nAnswer:"
                     end

            result = Legion::LLM.chat( # rubocop:disable Legion/HelperMigration/DirectLlm
              message: prompt,
              caller:  { extension: 'lex-knowledge' }
            )
            result.is_a?(Hash) ? result[:content] : result.content
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'knowledge.query.synthesize_answer')
            nil
          end
          private_class_method :synthesize_answer

          def format_source(chunk)
            {
              content:     chunk[:content],
              source_file: chunk.dig(:metadata, :source_file) || chunk[:source_file],
              heading:     chunk.dig(:metadata, :heading)     || chunk[:heading],
              chunk_index: chunk.dig(:metadata, :chunk_index) || chunk[:chunk_index],
              distance:    chunk[:distance] || chunk[:score]
            }
          end
          private_class_method :format_source

          def chunk_context(chunk)
            context = normalize_context(chunk[:metadata] || chunk[:source_context] || chunk[:context])
            if (context[:source_file].nil? || context[:chunk_index].nil?) && chunk[:id] && Helpers::ApolloModels.entry_available?
              row = Helpers::ApolloModels.entry.where(id: chunk[:id]).first
              context = context.merge(normalize_context(row_context(row))) if row
            end

            context[:source_file] ||= chunk[:source_file]
            context[:chunk_index] ||= chunk[:chunk_index]
            context[:heading] ||= chunk[:heading]
            context
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'knowledge.query.chunk_context')
            {}
          end
          private_class_method :chunk_context

          def row_context(row)
            values = row.respond_to?(:values) ? row.values : row
            values[:source_context] || values[:metadata] || values[:context]
          end
          private_class_method :row_context

          def normalize_context(context)
            normalized = case context
                         when String
                           context.strip.empty? ? {} : json_parse(context)
                         when Hash
                           context
                         else
                           {}
                         end

            normalized.transform_keys { |key| key.respond_to?(:to_sym) ? key.to_sym : key }
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'knowledge.query.normalize_context')
            {}
          end
          private_class_method :normalize_context

          def chunk_dedupe_key(chunk)
            chunk[:id] || chunk[:content_hash] || [
              chunk_context(chunk)[:source_file],
              chunk_context(chunk)[:chunk_index],
              chunk[:content]
            ]
          end
          private_class_method :chunk_dedupe_key

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
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'knowledge.query.emit_feedback_event')
            nil
          end
          private_class_method :emit_feedback_event

          def llm_available?
            defined?(Legion::LLM)
          end
          private_class_method :llm_available?

          def resolve_neighbor_radius(neighbor_radius)
            (neighbor_radius || settings[:query][:neighbor_radius]).to_i
          end
          private_class_method :resolve_neighbor_radius
        end
      end
    end
  end
end
