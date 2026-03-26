# frozen_string_literal: true

module Legion
  module Extensions
    module Knowledge
      module Runners
        module Corpus
          module_function

          def manifest_path(path:)
            Helpers::ManifestStore.store_path(corpus_path: path)
          end

          def corpus_stats(path:, extensions: nil)
            return { success: false, error: 'path does not exist' } unless ::File.exist?(path)

            opts = { path: path }
            opts[:extensions] = extensions if extensions
            entries = Helpers::Manifest.scan(**opts)
            chunk_count = entries.sum do |entry|
              sections = Helpers::Parser.parse(file_path: entry[:path])
              next 0 if sections.first&.key?(:error)

              Helpers::Chunker.chunk(sections: sections).size
            end

            {
              success:          true,
              path:             path,
              file_count:       entries.size,
              estimated_chunks: chunk_count,
              total_bytes:      entries.sum { |e| e[:size] }
            }
          rescue StandardError => e
            { success: false, error: e.message }
          end
        end
      end
    end
  end
end
