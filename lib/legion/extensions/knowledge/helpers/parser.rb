# frozen_string_literal: true

module Legion
  module Extensions
    module Knowledge
      module Helpers
        module Parser
          extend Legion::Logging::Helper

          module_function

          def parse(file_path:)
            ext = ::File.extname(file_path).downcase

            case ext
            when '.md'
              parse_markdown(file_path: file_path)
            when '.txt'
              parse_text(file_path: file_path)
            when '.pdf', '.docx'
              extract_via_data(file_path: file_path)
            else
              [{ error: 'unsupported format', source_file: file_path }]
            end
          end

          def parse_markdown(file_path:)
            content = ::File.read(file_path, encoding: 'utf-8')
            sections        = []
            current_heading = ::File.basename(file_path, '.*')
            current_lines   = []
            heading_stack   = {}

            content.each_line do |line|
              level = heading_level(line)
              if level
                flush_section(sections, current_heading, build_section_path(heading_stack), current_lines, file_path)
                title = line.sub(/^#+\s*/, '').chomp
                heading_stack.delete_if { |d, _| d >= level }
                heading_stack[level] = title
                current_heading = title
                current_lines   = []
              else
                current_lines << line
              end
            end

            flush_section(sections, current_heading, build_section_path(heading_stack), current_lines, file_path)

            sections.empty? ? [{ heading: ::File.basename(file_path, '.*'), section_path: [], content: content.strip, source_file: file_path }] : sections
          end

          def extract_via_data(file_path:)
            return [{ error: 'unsupported format', source_file: file_path }] unless defined?(::Legion::Data::Extract)

            result = ::Legion::Data::Extract.extract(file_path, type: :auto)
            return [{ error: 'extraction_failed', source_file: file_path, detail: result }] unless result.is_a?(Hash) && result[:text]

            heading = ::File.basename(file_path, '.*')
            [{ heading: heading, section_path: [], content: result[:text].strip, source_file: file_path }]
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'knowledge.parser.extract_via_data', file_path: file_path)
            [{ error: 'extraction_failed', source_file: file_path, detail: e.message }]
          end

          def parse_text(file_path:)
            content = ::File.read(file_path, encoding: 'utf-8')
            heading = ::File.basename(file_path, '.*')

            [{ heading: heading, section_path: [], content: content.strip, source_file: file_path }]
          end

          def flush_section(sections, heading, section_path, lines, file_path)
            content = lines.join.strip
            return if content.empty?

            sections << {
              heading:      heading,
              section_path: section_path.dup,
              content:      content,
              source_file:  file_path
            }
          end
          private_class_method :flush_section

          def heading_level(line)
            m = line.match(/^(\#{1,6})\s/)
            m ? m[1].length : nil
          end
          private_class_method :heading_level

          def build_section_path(stack)
            stack.sort.map { |_, title| title }
          end
          private_class_method :build_section_path
        end
      end
    end
  end
end
