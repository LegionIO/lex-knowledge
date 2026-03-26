# frozen_string_literal: true

module Legion
  module Extensions
    module Knowledge
      module Runners
        module Maintenance
          module_function

          def detect_orphans(path:)
            manifest_files = load_manifest_files(path)
            apollo_files   = load_apollo_source_files

            orphan_files = apollo_files - manifest_files

            {
              success:              true,
              orphan_count:         orphan_files.size,
              orphan_files:         orphan_files,
              total_apollo_chunks:  count_apollo_chunks,
              total_manifest_files: manifest_files.size
            }
          rescue StandardError => e
            { success: false, error: e.message }
          end

          def cleanup_orphans(path:, dry_run: true)
            detection = detect_orphans(path: path)
            return detection unless detection[:success]
            return detection.merge(archived: 0, files_cleaned: 0, dry_run: dry_run) if detection[:orphan_count].zero?
            return detection.merge(archived: detection[:orphan_count], files_cleaned: detection[:orphan_files].size, dry_run: true) if dry_run

            archived = archive_orphan_entries(detection[:orphan_files])

            { success: true, archived: archived, files_cleaned: detection[:orphan_files].size, dry_run: false }
          rescue StandardError => e
            { success: false, error: e.message }
          end

          def reindex(path:)
            store_path = Helpers::ManifestStore.store_path(corpus_path: path)
            ::FileUtils.rm_f(store_path)

            Runners::Ingest.ingest_corpus(path: path, force: true)
          end

          def load_manifest_files(path)
            manifest = Helpers::ManifestStore.load(corpus_path: path)
            manifest.map { |e| e[:path] || e['path'] }.compact.uniq
          end
          private_class_method :load_manifest_files

          def load_apollo_source_files
            return [] unless defined?(Legion::Data::Model::ApolloEntry)

            Legion::Data::Model::ApolloEntry
              .where(Sequel.pg_array_op(:tags).contains(Sequel.pg_array(['document_chunk'])))
              .exclude(status: 'archived')
              .select_map(Sequel.lit("source_context->>'source_file'"))
              .compact
              .uniq
          rescue StandardError
            []
          end
          private_class_method :load_apollo_source_files

          def count_apollo_chunks
            return 0 unless defined?(Legion::Data::Model::ApolloEntry)

            Legion::Data::Model::ApolloEntry
              .where(Sequel.pg_array_op(:tags).contains(Sequel.pg_array(['document_chunk'])))
              .exclude(status: 'archived')
              .count
          rescue StandardError
            0
          end
          private_class_method :count_apollo_chunks

          def archive_orphan_entries(orphan_files)
            return 0 unless defined?(Legion::Data::Model::ApolloEntry)

            count = 0
            orphan_files.each do |file|
              updated = Legion::Data::Model::ApolloEntry
                .where(Sequel.pg_array_op(:tags).contains(Sequel.pg_array(['document_chunk'])))
                .where(Sequel.lit("source_context->>'source_file' = ?", file))
                .exclude(status: 'archived')
                .update(status: 'archived', updated_at: Time.now)
              count += updated
            end
            count
          rescue StandardError
            0
          end
          private_class_method :archive_orphan_entries
        end
      end
    end
  end
end
