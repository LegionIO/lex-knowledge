# frozen_string_literal: true

module Legion
  module Extensions
    module Knowledge
      module Runners
        module Maintenance # rubocop:disable Legion/Extension/RunnerIncludeHelpers
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
          rescue StandardError => e
            { success: false, error: e.message }
          end

          def health(path:)
            resolved = path || (Legion::Settings.dig(:knowledge, :corpus_path) if defined?(Legion::Settings))
            return { success: false, error: 'corpus_path is required' } if resolved.nil? || resolved.to_s.empty?

            scan_entries  = Helpers::Manifest.scan(path: resolved)
            store_path    = Helpers::ManifestStore.store_path(corpus_path: resolved)
            manifest_file = ::File.exist?(store_path)
            last_ingest   = manifest_file ? ::File.mtime(store_path).iso8601 : nil

            {
              success: true,
              local:   build_local_stats(resolved, scan_entries, manifest_file, last_ingest),
              apollo:  build_apollo_stats,
              sync:    build_sync_stats(resolved, scan_entries)
            }
          rescue StandardError => e
            { success: false, error: e.message }
          end

          def quality_report(limit: nil)
            resolved_limit = limit || settings_quality_limit

            {
              success:        true,
              hot_chunks:     hot_chunks(resolved_limit),
              cold_chunks:    cold_chunks(resolved_limit),
              low_confidence: low_confidence_chunks(resolved_limit),
              poor_retrieval: [],
              summary:        quality_summary
            }
          rescue StandardError => e
            { success: false, error: e.message }
          end

          def build_local_stats(path, scan_entries, manifest_file, last_ingest)
            {
              corpus_path:     path,
              file_count:      scan_entries.size,
              total_bytes:     scan_entries.sum { |e| e[:size] },
              manifest_exists: manifest_file,
              last_ingest:     last_ingest
            }
          end
          private_class_method :build_local_stats

          def build_apollo_stats
            return apollo_defaults unless defined?(Legion::Data::Model::ApolloEntry)

            base  = Legion::Data::Model::ApolloEntry
                    .where(Sequel.pg_array_op(:tags).contains(Sequel.pg_array(['document_chunk'])))
                    .exclude(status: 'archived')
            total = base.count
            return apollo_defaults if total.zero?

            rows = base.select(:confidence, :status, :access_count, :embedding, :created_at).all
            apollo_stats_from_rows(base, rows, total)
          rescue StandardError => _e
            apollo_defaults
          end
          private_class_method :build_apollo_stats

          def apollo_stats_from_rows(base, rows, total)
            confidences     = rows.map { |r| r[:confidence].to_f }
            with_embeddings = rows.count { |r| !r[:embedding].nil? }
            stale_threshold = settings_stale_threshold
            timestamps      = rows.map { |r| r[:created_at] }

            {
              total_chunks:        total,
              by_status:           base.group_and_count(:status).as_hash(:status, :count).transform_keys(&:to_sym),
              embedding_coverage:  (with_embeddings.to_f / total).round(4),
              avg_confidence:      confidences.sum / confidences.size.to_f,
              confidence_range:    confidences.minmax,
              stale_count:         confidences.count { |c| c < stale_threshold },
              never_accessed:      rows.count { |r| r[:access_count].to_i.zero? },
              unique_source_files: load_apollo_source_files.size,
              oldest_chunk:        timestamps.min&.iso8601,
              newest_chunk:        timestamps.max&.iso8601
            }
          end
          private_class_method :apollo_stats_from_rows

          def apollo_defaults
            {
              total_chunks:        0,
              by_status:           {},
              embedding_coverage:  0.0,
              avg_confidence:      0.0,
              confidence_range:    [0.0, 0.0],
              stale_count:         0,
              never_accessed:      0,
              unique_source_files: 0,
              oldest_chunk:        nil,
              newest_chunk:        nil
            }
          end
          private_class_method :apollo_defaults

          def build_sync_stats(path, scan_entries)
            manifest_paths = load_manifest_files(path)
            apollo_paths   = load_apollo_source_files
            scan_paths     = scan_entries.map { |e| e[:path] }

            {
              orphan_count:  (apollo_paths - manifest_paths).size,
              missing_count: (scan_paths - apollo_paths).size
            }
          end
          private_class_method :build_sync_stats

          def load_manifest_files(path)
            manifest = Helpers::ManifestStore.load(corpus_path: path)
            manifest.filter_map { |e| e[:path] }.uniq
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
          rescue StandardError => _e
            []
          end
          private_class_method :load_apollo_source_files

          def count_apollo_chunks
            return 0 unless defined?(Legion::Data::Model::ApolloEntry)

            Legion::Data::Model::ApolloEntry
              .where(Sequel.pg_array_op(:tags).contains(Sequel.pg_array(['document_chunk'])))
              .exclude(status: 'archived')
              .count
          rescue StandardError => _e
            0
          end
          private_class_method :count_apollo_chunks

          def archive_orphan_entries(orphan_files)
            return 0 unless defined?(Legion::Data::Model::ApolloEntry)

            Legion::Data::Model::ApolloEntry
              .where(Sequel.pg_array_op(:tags).contains(Sequel.pg_array(['document_chunk'])))
              .where(Sequel.lit("source_context->>'source_file' IN ?", orphan_files))
              .exclude(status: 'archived')
              .update(status: 'archived', updated_at: Time.now)
          end
          private_class_method :archive_orphan_entries

          def hot_chunks(limit)
            return [] unless defined?(Legion::Data::Model::ApolloEntry)

            Legion::Data::Model::ApolloEntry
              .where(Sequel.pg_array_op(:tags).contains(Sequel.pg_array(['document_chunk'])))
              .exclude(status: 'archived')
              .where { access_count.positive? }
              .order(Sequel.desc(:access_count))
              .limit(limit)
              .select_map([:id, :access_count, :confidence,
                           Sequel.lit("source_context->>'source_file' AS source_file")])
              .map { |r| { id: r[0], access_count: r[1], confidence: r[2], source_file: r[3] } }
          rescue StandardError => _e
            []
          end
          private_class_method :hot_chunks

          def cold_chunks(limit)
            return [] unless defined?(Legion::Data::Model::ApolloEntry)

            days   = settings_cold_chunk_days
            cutoff = Time.now - (days * 86_400)

            Legion::Data::Model::ApolloEntry
              .where(Sequel.pg_array_op(:tags).contains(Sequel.pg_array(['document_chunk'])))
              .exclude(status: 'archived')
              .where(access_count: 0)
              .where { created_at < cutoff }
              .order(:created_at)
              .limit(limit)
              .select_map([:id, :confidence, :created_at,
                           Sequel.lit("source_context->>'source_file' AS source_file")])
              .map { |r| { id: r[0], confidence: r[1], created_at: r[2]&.iso8601, source_file: r[3] } }
          rescue StandardError => _e
            []
          end
          private_class_method :cold_chunks

          def low_confidence_chunks(limit)
            return [] unless defined?(Legion::Data::Model::ApolloEntry)

            threshold = settings_stale_threshold

            Legion::Data::Model::ApolloEntry
              .where(Sequel.pg_array_op(:tags).contains(Sequel.pg_array(['document_chunk'])))
              .exclude(status: 'archived')
              .where { confidence < threshold }
              .order(:confidence)
              .limit(limit)
              .select_map([:id, :confidence, :access_count,
                           Sequel.lit("source_context->>'source_file' AS source_file")])
              .map { |r| { id: r[0], confidence: r[1], access_count: r[2], source_file: r[3] } }
          rescue StandardError => _e
            []
          end
          private_class_method :low_confidence_chunks

          def quality_summary
            defaults = { total_queries: 0, avg_retrieval_score: nil, chunks_never_accessed: 0,
                         chunks_below_threshold: 0 }
            return defaults unless defined?(Legion::Data::Model::ApolloEntry)

            base = Legion::Data::Model::ApolloEntry
                   .where(Sequel.pg_array_op(:tags).contains(Sequel.pg_array(['document_chunk'])))
                   .exclude(status: 'archived')

            {
              total_queries:          query_count,
              avg_retrieval_score:    nil,
              chunks_never_accessed:  base.where(access_count: 0).count,
              chunks_below_threshold: base.where { confidence < settings_stale_threshold }.count
            }
          rescue StandardError => _e
            defaults
          end
          private_class_method :quality_summary

          def query_count
            return 0 unless defined?(Legion::Data::Model::ApolloAccessLog)

            Legion::Data::Model::ApolloAccessLog.where(action: 'knowledge_query').count
          rescue StandardError => _e
            0
          end
          private_class_method :query_count

          def settings_stale_threshold
            return 0.3 unless defined?(Legion::Settings)

            Legion::Settings.dig(:knowledge, :maintenance, :stale_threshold) || 0.3
          rescue StandardError => _e
            0.3
          end
          private_class_method :settings_stale_threshold

          def settings_cold_chunk_days
            return 7 unless defined?(Legion::Settings)

            Legion::Settings.dig(:knowledge, :maintenance, :cold_chunk_days) || 7
          rescue StandardError => _e
            7
          end
          private_class_method :settings_cold_chunk_days

          def settings_quality_limit
            return 10 unless defined?(Legion::Settings)

            Legion::Settings.dig(:knowledge, :maintenance, :quality_report_limit) || 10
          rescue StandardError => _e
            10
          end
          private_class_method :settings_quality_limit
        end
      end
    end
  end
end
