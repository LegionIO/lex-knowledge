# frozen_string_literal: true

require 'digest'

module Legion
  module Extensions
    module Knowledge
      module Helpers
        module Chunker
          extend Legion::Logging::Helper
          extend Legion::Settings::Helper

          CHARS_PER_TOKEN = 4

          module_function

          def chunk(sections:, max_tokens: nil, overlap_tokens: nil)
            resolved_max     = max_tokens     || settings[:chunker][:max_tokens]
            resolved_overlap = overlap_tokens || settings[:chunker][:overlap_tokens]

            max_chars     = resolved_max * CHARS_PER_TOKEN
            overlap_chars = resolved_overlap * CHARS_PER_TOKEN

            chunks = []
            sections.each do |section|
              chunks.concat(split_section(section, max_chars, overlap_chars))
            end
            chunks
          end

          def split_section(section, max_chars, overlap_chars)
            paragraphs = section[:content].split(/\n\n+/)
            chunks     = []
            buffer     = ''
            chunk_idx  = 0

            paragraphs.each do |para|
              candidate = buffer.empty? ? para : "#{buffer}\n\n#{para}"

              if candidate.length <= max_chars
                buffer = candidate
              else
                unless buffer.empty?
                  chunks << build_chunk(section, buffer, chunk_idx)
                  chunk_idx += 1
                  tail   = buffer.length > overlap_chars ? buffer[-overlap_chars..] : buffer
                  buffer = tail.empty? ? para : "#{tail}\n\n#{para}"
                end

                if para.length > max_chars
                  para.chars.each_slice(max_chars).with_index do |slice, i|
                    text = slice.join
                    chunks << build_chunk(section, text, chunk_idx + i)
                  end
                  chunk_idx += (para.length.to_f / max_chars).ceil
                  buffer = ''
                else
                  buffer = para
                end
              end
            end

            chunks << build_chunk(section, buffer, chunk_idx) unless buffer.empty?
            chunks
          end
          private_class_method :split_section

          # Hash must match Legion::Extensions::Apollo::Helpers::Writeback.content_hash
          # so knowledge chunks deduplicate consistently with Apollo writeback and still
          # fit older apollo_entries.content_hash columns fixed at MD5 length.
          def build_chunk(section, content, index)
            {
              content:      content,
              heading:      section[:heading],
              section_path: section[:section_path],
              source_file:  section[:source_file],
              token_count:  (content.length.to_f / CHARS_PER_TOKEN).ceil,
              chunk_index:  index,
              content_hash: apollo_compatible_content_hash(content)
            }
          end
          private_class_method :build_chunk

          def apollo_compatible_content_hash(content)
            if defined?(Legion::Extensions::Apollo::Helpers::Writeback)
              Legion::Extensions::Apollo::Helpers::Writeback.content_hash(content)
            else
              # Fallback when apollo isn't loaded - match its MD5+normalize semantics
              # so future apollo-backed lookups still work.
              normalized = content.to_s.strip.downcase.gsub(/\s+/, ' ')
              ::Digest::MD5.hexdigest(normalized)
            end
          end
          private_class_method :apollo_compatible_content_hash
        end
      end
    end
  end
end
