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

          def ingest_corpus(path: nil, monitors: nil, dry_run: false, force: false)
            return ingest_monitors(monitors: monitors, dry_run: dry_run, force: force) if monitors&.any?
            raise ArgumentError, 'path is required when monitors is not provided' if path.nil?

            ingest_corpus_path(path: path, dry_run: dry_run, force: force)
          rescue ArgumentError => e
            { success: false, error: e.message }
          end

          def ingest_corpus_path(path:, dry_run: false, force: false)
            current  = Helpers::Manifest.scan(path: path)
            previous = force ? [] : Helpers::ManifestStore.load(corpus_path: path)
            delta    = Helpers::Manifest.diff(current: current, previous: previous)

            to_process     = delta[:added] + delta[:changed]
            chunks_created = 0
            chunks_skipped = 0
            chunks_updated = 0

            to_process.each do |file_path|
              result = process_file(file_path, dry_run: dry_run, force: force)
              chunks_created += result[:created]
              chunks_skipped += result[:skipped]
              chunks_updated += result[:updated]
            end

            delta[:removed].each { |file_path| retire_file(file_path: file_path) } unless dry_run

            Helpers::ManifestStore.save(corpus_path: path, manifest: current) unless dry_run

            {
              success:        true,
              files_scanned:  current.size,
              files_added:    delta[:added].size,
              files_changed:  delta[:changed].size,
              files_removed:  delta[:removed].size,
              chunks_created: chunks_created,
              chunks_skipped: chunks_skipped,
              chunks_updated: chunks_updated
            }
          rescue StandardError => e
            { success: false, error: e.message }
          end
          private_class_method :ingest_corpus_path

          def ingest_monitors(monitors:, dry_run: false, force: false)
            results = monitors.map do |monitor|
              ingest_corpus(path: monitor[:path], dry_run: dry_run, force: force)
            rescue StandardError => e
              { success: false, path: monitor[:path], error: e.message }
            end

            total = {
              files_scanned:  0,
              files_added:    0,
              files_changed:  0,
              files_removed:  0,
              chunks_created: 0,
              chunks_skipped: 0,
              chunks_updated: 0
            }
            results.each do |r|
              next unless r[:success]

              total.each_key { |k| total[k] += r[k].to_i }
            end

            { success: true, monitors_processed: results.size, **total }
          rescue StandardError => e
            { success: false, error: e.message }
          end
          private_class_method :ingest_monitors

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
            paired  = if dry_run
                        chunks.map { |c| { chunk: c, embedding: nil } }
                      else
                        batch_embed_chunks(chunks, force: force)
                      end

            created = 0
            skipped = 0
            updated = 0

            paired.each do |p|
              outcome = upsert_chunk_with_embedding(p[:chunk], p[:embedding], dry_run: dry_run, force: force, exists: p[:exists] || false)
              case outcome
              when :created then created += 1
              when :skipped then skipped += 1
              when :updated then updated += 1
              end
            end

            { created: created, skipped: skipped, updated: updated }
          end
          private_class_method :process_file

          def batch_embed_chunks(chunks, force:)
            exists_map = force ? {} : build_exists_map(chunks)
            return paired_without_embed(chunks, exists_map) unless llm_embed_available?

            needs_embed = force ? chunks : chunks.reject { |c| exists_map[c[:content_hash]] }
            embed_map   = needs_embed.empty? ? {} : build_embed_map(needs_embed)

            chunks.map { |c| { chunk: c, embedding: embed_map[c[:content_hash]], exists: exists_map.fetch(c[:content_hash], false) } }
          rescue StandardError
            paired_without_embed(chunks, {})
          end
          private_class_method :batch_embed_chunks

          def build_exists_map(chunks)
            chunks.to_h { |c| [c[:content_hash], chunk_exists?(c[:content_hash])] }
          end
          private_class_method :build_exists_map

          def llm_embed_available?
            defined?(Legion::LLM) && Legion::LLM.respond_to?(:embed_batch)
          end
          private_class_method :llm_embed_available?

          def paired_without_embed(chunks, exists_map)
            chunks.map { |c| { chunk: c, embedding: nil, exists: exists_map.fetch(c[:content_hash], false) } }
          end
          private_class_method :paired_without_embed

          def build_embed_map(needs_embed)
            results = Legion::LLM.embed_batch(needs_embed.map { |c| c[:content] })
            results.each_with_object({}) do |r, h|
              h[needs_embed[r[:index]][:content_hash]] = r[:vector] unless r[:error]
            end
          rescue StandardError
            {}
          end
          private_class_method :build_embed_map

          def upsert_chunk_with_embedding(chunk, embedding, dry_run: false, force: false, exists: false)
            return :created if dry_run
            return :created unless defined?(Legion::Extensions::Apollo)
            return :skipped if !force && exists

            ingest_to_apollo(chunk, embedding)
            force ? :updated : :created
          rescue StandardError
            :skipped
          end
          private_class_method :upsert_chunk_with_embedding

          def chunk_exists?(content_hash)
            return false unless defined?(Legion::Data::Model::ApolloEntry)

            Legion::Data::Model::ApolloEntry
              .where(Sequel.pg_array_op(:tags).contains(Sequel.pg_array(['document_chunk'])))
              .where(Sequel.like(:content, "%#{content_hash}%"))
              .any?
          rescue StandardError
            false
          end
          private_class_method :chunk_exists?

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

          def retire_file(file_path:)
            return unless defined?(Legion::Apollo)
            return unless Legion::Apollo.respond_to?(:ingest) && Legion::Apollo.started?

            Legion::Apollo.ingest(
              content:      file_path,
              content_type: 'document_retired',
              tags:         [file_path, 'retired', 'document_chunk'].uniq,
              metadata:     { source_file: file_path, retired: true }
            )
          rescue StandardError
            nil
          end
          private_class_method :retire_file
        end
      end
    end
  end
end
