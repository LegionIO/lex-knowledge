# frozen_string_literal: true

require 'digest'
require 'find'

module Legion
  module Extensions
    module Knowledge
      module Helpers
        module Manifest
          module_function

          def scan(path:, extensions: %w[.md .txt .docx .pdf])
            results = []

            Find.find(path) do |entry|
              basename = ::File.basename(entry)
              Find.prune if basename.start_with?('.')

              next unless ::File.file?(entry)
              next unless extensions.include?(::File.extname(entry).downcase)

              results << build_entry(entry)
            end

            results
          end

          def diff(current:, previous:)
            current_map  = current.to_h { |e| [e[:path], e[:sha256]] }
            previous_map = previous.to_h { |e| [e[:path], e[:sha256]] }

            added   = current_map.keys - previous_map.keys
            removed = previous_map.keys - current_map.keys
            changed = current_map.keys.select do |p|
              previous_map.key?(p) && previous_map[p] != current_map[p]
            end

            { added: added, changed: changed, removed: removed }
          end

          def build_entry(path)
            {
              path:   path,
              size:   ::File.size(path),
              mtime:  ::File.mtime(path),
              sha256: ::Digest::SHA256.file(path).hexdigest
            }
          end
          private_class_method :build_entry
        end
      end
    end
  end
end
