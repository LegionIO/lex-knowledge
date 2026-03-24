# frozen_string_literal: true

require 'digest'

module Legion
  module Extensions
    module Knowledge
      module Helpers
        module Chunker
          CHARS_PER_TOKEN = 4

          module_function

          def chunk(sections:, max_tokens: nil, overlap_tokens: nil)
            resolved_max     = max_tokens     || settings_max_tokens     || 512
            resolved_overlap = overlap_tokens || settings_overlap_tokens || 128

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

          def build_chunk(section, content, index)
            {
              content:      content,
              heading:      section[:heading],
              section_path: section[:section_path],
              source_file:  section[:source_file],
              token_count:  (content.length.to_f / CHARS_PER_TOKEN).ceil,
              chunk_index:  index,
              content_hash: ::Digest::SHA256.hexdigest(content)
            }
          end
          private_class_method :build_chunk

          def settings_max_tokens
            return nil unless defined?(Legion::Settings)

            Legion::Settings.dig(:knowledge, :chunker, :max_tokens)
          rescue StandardError
            nil
          end
          private_class_method :settings_max_tokens

          def settings_overlap_tokens
            return nil unless defined?(Legion::Settings)

            Legion::Settings.dig(:knowledge, :chunker, :overlap_tokens)
          rescue StandardError
            nil
          end
          private_class_method :settings_overlap_tokens
        end
      end
    end
  end
end
