# frozen_string_literal: true

require 'digest'

module Legion
  module Extensions
    module Knowledge
      module Helpers
        module Manifest
          module_function

          def scan(path:, extensions: %w[.md .txt .docx .pdf])
            results = []
            walk(path, extensions, results)
            results
          end

          def walk(entry, extensions, results)
            basename = ::File.basename(entry)
            return if basename.start_with?('.')

            if ::File.directory?(entry)
              ::Dir.children(entry).each { |c| walk(::File.join(entry, c), extensions, results) }
            elsif ::File.file?(entry) && extensions.include?(::File.extname(entry).downcase)
              results << build_entry(entry)
            end
          rescue Errno::EPERM, Errno::EACCES, Errno::ELOOP, Errno::ENOENT => e
            log.debug("[manifest] skipping unreadable #{entry}: #{e.class}: #{e.message}")
          end
          private_class_method :walk

          def log
            Legion::Logging
          end
          private_class_method :log

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
