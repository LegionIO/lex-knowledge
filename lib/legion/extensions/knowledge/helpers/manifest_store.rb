# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'legion/json'
require 'tempfile'

module Legion
  module Extensions
    module Knowledge
      module Helpers
        module ManifestStore
          extend Legion::Logging::Helper
          extend Legion::JSON::Helper

          module_function

          STORE_DIR = ::File.expand_path('~/.legionio/knowledge').freeze

          def load(corpus_path:)
            path = store_path(corpus_path: corpus_path)
            return [] unless ::File.exist?(path)

            raw = ::File.read(path, encoding: 'utf-8')
            json_parse(raw)
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'knowledge.manifest_store.load', corpus_path: corpus_path)
            []
          end

          def save(corpus_path:, manifest:)
            ::FileUtils.mkdir_p(STORE_DIR)
            path = store_path(corpus_path: corpus_path)
            tmp  = "#{path}.tmp"
            ::File.write(tmp, json_generate(manifest.map { |e| serialize_entry(e) }))
            ::File.rename(tmp, path)
            true
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'knowledge.manifest_store.save', corpus_path: corpus_path)
            false
          end

          def store_path(corpus_path:)
            hash = ::Digest::SHA256.hexdigest(corpus_path.to_s)[0, 16]
            ::File.join(STORE_DIR, "#{hash}.manifest.json")
          end

          def serialize_entry(entry)
            entry.merge(mtime: entry[:mtime].to_s)
          end
          private_class_method :serialize_entry
        end
      end
    end
  end
end
