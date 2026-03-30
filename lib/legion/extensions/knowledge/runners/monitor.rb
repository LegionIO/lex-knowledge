# frozen_string_literal: true

module Legion
  module Extensions
    module Knowledge
      module Runners
        module Monitor # rubocop:disable Legion/Extension/RunnerIncludeHelpers
          module_function

          DEFAULT_EXTENSIONS = %w[.md .txt].freeze

          def resolve_monitors
            monitors = Array(read_monitors_setting)
            legacy   = read_legacy_corpus_path

            if legacy && !legacy.empty? && monitors.none? { |m| m[:path] == legacy }
              monitors << { path: legacy, extensions: %w[.md .txt .docx .pdf], label: 'legacy' }
            end

            monitors
          rescue StandardError => _e
            []
          end

          def add_monitor(path:, extensions: nil, label: nil)
            abs_path = File.expand_path(path)
            return { success: false, error: "Path #{abs_path} does not exist or is not a directory" } unless File.directory?(abs_path)

            existing = Array(read_monitors_setting)
            return { success: false, error: "Path #{abs_path} is already registered" } if existing.any? { |m| m[:path] == abs_path }

            entry = {
              path:       abs_path,
              extensions: extensions || DEFAULT_EXTENSIONS.dup,
              label:      label || File.basename(abs_path),
              added_at:   Time.now.utc.iso8601
            }

            existing << entry
            persist_monitors(existing)

            { success: true, monitor: entry }
          rescue StandardError => e
            { success: false, error: e.message }
          end

          def remove_monitor(identifier:)
            existing = Array(read_monitors_setting)
            found = existing.find { |m| m[:path] == identifier || m[:label] == identifier }
            return { success: false, error: "Monitor '#{identifier}' not found" } unless found

            existing.delete(found)
            persist_monitors(existing)

            { success: true, removed: found }
          rescue StandardError => e
            { success: false, error: e.message }
          end

          def list_monitors
            { success: true, monitors: resolve_monitors }
          rescue StandardError => e
            { success: false, error: e.message }
          end

          def monitor_status
            monitors    = resolve_monitors
            total_files = 0

            monitors.each do |m|
              scan = Helpers::Manifest.scan(path: m[:path], extensions: m[:extensions])
              total_files += scan.size
            rescue StandardError => _e
              next
            end

            { success: true, total_monitors: monitors.size, total_files: total_files }
          rescue StandardError => e
            { success: false, error: e.message }
          end

          # --- private helpers ---

          def read_monitors_setting
            return nil unless defined?(Legion::Settings) && !Legion::Settings[:knowledge].nil?

            Legion::Settings.dig(:knowledge, :monitors)
          rescue StandardError => _e
            nil
          end
          private_class_method :read_monitors_setting

          def read_legacy_corpus_path
            return nil unless defined?(Legion::Settings) && !Legion::Settings[:knowledge].nil?

            Legion::Settings.dig(:knowledge, :corpus_path)
          rescue StandardError => _e
            nil
          end
          private_class_method :read_legacy_corpus_path

          def persist_monitors(monitors)
            return false unless defined?(Legion::Settings)

            loader = Legion::Settings.loader
            knowledge = loader.settings[:knowledge] || {}
            knowledge[:monitors] = monitors
            loader.settings[:knowledge] = knowledge
            true
          rescue StandardError => _e
            false
          end
          private_class_method :persist_monitors
        end
      end
    end
  end
end
