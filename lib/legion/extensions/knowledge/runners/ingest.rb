# frozen_string_literal: true

module Legion
  module Extensions
    module Knowledge
      module Runners
        module Ingest
          module_function

          def scan_corpus(path:, extensions: nil)
            opts = { path: path }
            opts[:extensions] = extensions if extensions

            entries = Helpers::Manifest.scan(**opts)

            {
              success:     true,
              path:        path,
              file_count:  entries.size,
              total_bytes: entries.sum { |e| e[:size] },
              files:       entries.map { |e| e[:path] }
            }
          end

          def ingest_corpus(path:, dry_run: false, force: false)
            entries = Helpers::Manifest.scan(path: path)

            files_scanned   = entries.size
            chunks_created  = 0
            chunks_skipped  = 0
            chunks_updated  = 0

            entries.each do |entry|
              result = process_file(entry[:path], dry_run: dry_run, force: force)
              chunks_created  += result[:created]
              chunks_skipped  += result[:skipped]
              chunks_updated  += result[:updated]
            end

            {
              success:        true,
              files_scanned:  files_scanned,
              chunks_created: chunks_created,
              chunks_skipped: chunks_skipped,
              chunks_updated: chunks_updated
            }
          rescue StandardError => e
            { success: false, error: e.message }
          end

          def ingest_file(file_path:, force: false)
            result = process_file(file_path, dry_run: false, force: force)

            {
              success:        true,
              file:           file_path,
              chunks_created: result[:created],
              chunks_skipped: result[:skipped],
              chunks_updated: result[:updated]
            }
          rescue StandardError => e
            { success: false, error: e.message }
          end

          def process_file(file_path, dry_run: false, force: false)
            sections = Helpers::Parser.parse(file_path: file_path)
            return { created: 0, skipped: 0, updated: 0 } if sections.first&.key?(:error)

            chunks  = Helpers::Chunker.chunk(sections: sections)
            created = 0
            skipped = 0
            updated = 0

            chunks.each do |chunk|
              outcome = upsert_chunk(chunk, dry_run: dry_run, force: force)
              case outcome
              when :created then created += 1
              when :skipped then skipped += 1
              when :updated then updated += 1
              end
            end

            { created: created, skipped: skipped, updated: updated }
          end
          private_class_method :process_file

          def upsert_chunk(chunk, dry_run: false, force: false)
            return :created if dry_run

            return :created unless defined?(Legion::Extensions::Apollo)

            return :skipped if !force && chunk_exists?(chunk[:content_hash])

            embedding = generate_embedding(chunk[:content])
            ingest_to_apollo(chunk, embedding)

            force ? :updated : :created
          rescue StandardError
            :skipped
          end
          private_class_method :upsert_chunk

          def chunk_exists?(content_hash)
            return false unless defined?(Legion::Extensions::Apollo)

            Legion::Extensions::Apollo::Runners::Knowledge.retrieve_relevant(
              query:  content_hash,
              limit:  1,
              tags:   ['document_chunk'],
              filter: { content_hash: content_hash }
            ).any?
          rescue StandardError
            false
          end
          private_class_method :chunk_exists?

          def generate_embedding(content)
            return nil unless defined?(Legion::Extensions::Apollo)
            return nil unless defined?(Legion::Extensions::Apollo::Helpers::Embedding)

            Legion::Extensions::Apollo::Helpers::Embedding.generate(content)
          rescue StandardError
            nil
          end
          private_class_method :generate_embedding

          def ingest_to_apollo(chunk, embedding)
            return unless defined?(Legion::Extensions::Apollo)

            payload = {
              content:      chunk[:content],
              content_type: 'document_chunk',
              content_hash: chunk[:content_hash],
              tags:         [chunk[:source_file], chunk[:heading], 'document_chunk'].compact.uniq,
              metadata:     {
                source_file:  chunk[:source_file],
                heading:      chunk[:heading],
                section_path: chunk[:section_path],
                chunk_index:  chunk[:chunk_index],
                token_count:  chunk[:token_count]
              }
            }
            payload[:embedding] = embedding if embedding

            Legion::Extensions::Apollo::Runners::Knowledge.handle_ingest(**payload)
          end
          private_class_method :ingest_to_apollo
        end
      end
    end
  end
end
