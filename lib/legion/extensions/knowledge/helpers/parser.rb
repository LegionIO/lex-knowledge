# frozen_string_literal: true

module Legion
  module Extensions
    module Knowledge
      module Helpers
        module Parser
          module_function

          def parse(file_path:)
            ext = ::File.extname(file_path).downcase

            case ext
            when '.md'
              parse_markdown(file_path: file_path)
            when '.txt'
              parse_text(file_path: file_path)
            else
              [{ error: 'unsupported format', source_file: file_path }]
            end
          end

          def parse_markdown(file_path:)
            content = ::File.read(file_path, encoding: 'utf-8')
            sections = []
            current_heading = ::File.basename(file_path, '.*')
            current_lines   = []
            section_path    = []

            content.each_line do |line|
              if line.start_with?('# ')
                flush_section(sections, current_heading, section_path, current_lines, file_path) unless current_lines.empty?
                current_heading = line.sub(/^#+\s*/, '').chomp
                section_path    = [current_heading]
                current_lines   = []
              elsif line.start_with?('## ')
                flush_section(sections, current_heading, section_path, current_lines, file_path) unless current_lines.empty?
                current_heading = line.sub(/^#+\s*/, '').chomp
                section_path    = section_path.first(1) + [current_heading]
                current_lines   = []
              else
                current_lines << line
              end
            end

            flush_section(sections, current_heading, section_path, current_lines, file_path) unless current_lines.empty?

            sections.empty? ? [{ heading: ::File.basename(file_path, '.*'), section_path: [], content: content.strip, source_file: file_path }] : sections
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
        end
      end
    end
  end
end
