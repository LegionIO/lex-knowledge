# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions::Knowledge::Helpers::Parser do
  subject(:parser) { described_class }

  describe '.parse_markdown' do
    it 'splits content on # headings into sections' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'doc.md')
        File.write(path, "# Introduction\nHello world\n\n# Conclusion\nGoodbye\n")
        result = parser.parse_markdown(file_path: path)
        expect(result.size).to eq(2)
        expect(result.map { |s| s[:heading] }).to include('Introduction', 'Conclusion')
      end
    end

    it 'includes source_file in each section' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'guide.md')
        File.write(path, "# Section\nContent here\n")
        result = parser.parse_markdown(file_path: path)
        expect(result.first[:source_file]).to eq(path)
      end
    end

    it 'returns a single section for a file with no headings' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'plain.md')
        File.write(path, "Just some plain text\nwithout any headings\n")
        result = parser.parse_markdown(file_path: path)
        expect(result.size).to eq(1)
        expect(result.first[:content]).to include('Just some plain text')
      end
    end

    it 'populates section_path for top-level headings' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'doc.md')
        File.write(path, "# Top\nContent\n")
        result = parser.parse_markdown(file_path: path)
        expect(result.first[:section_path]).to eq(['Top'])
      end
    end

    it 'returns non-empty content for each section' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'multi.md')
        File.write(path, "# Alpha\nFirst section text\n\n# Beta\nSecond section text\n")
        result = parser.parse_markdown(file_path: path)
        result.each do |section|
          expect(section[:content]).not_to be_empty
        end
      end
    end
  end

  describe '.parse_text' do
    it 'returns a single section with the filename as heading' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'notes.txt')
        File.write(path, "These are notes\nSecond line\n")
        result = parser.parse_text(file_path: path)
        expect(result.size).to eq(1)
        expect(result.first[:heading]).to eq('notes')
      end
    end

    it 'includes all file content in the section' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'data.txt')
        File.write(path, "Line one\nLine two\nLine three\n")
        result = parser.parse_text(file_path: path)
        expect(result.first[:content]).to include('Line one')
        expect(result.first[:content]).to include('Line three')
      end
    end

    it 'includes source_file' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'readme.txt')
        File.write(path, 'content')
        result = parser.parse_text(file_path: path)
        expect(result.first[:source_file]).to eq(path)
      end
    end
  end

  describe '.parse' do
    it 'dispatches .md files to parse_markdown' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'doc.md')
        File.write(path, "# Title\nBody\n")
        result = parser.parse(file_path: path)
        expect(result).to be_an(Array)
        expect(result.first).to include(:heading, :content, :source_file)
      end
    end

    it 'dispatches .txt files to parse_text' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'note.txt')
        File.write(path, 'plain text')
        result = parser.parse(file_path: path)
        expect(result.first[:heading]).to eq('note')
      end
    end

    it 'returns an unsupported format error for .docx files when Data::Extract is absent' do
      hide_const('Legion::Data::Extract') if defined?(Legion::Data::Extract)
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'report.docx')
        File.write(path, 'binary blob')
        result = parser.parse(file_path: path)
        expect(result.first[:error]).to eq('unsupported format')
      end
    end

    it 'returns an unsupported format error for .pdf files when Data::Extract is absent' do
      hide_const('Legion::Data::Extract') if defined?(Legion::Data::Extract)
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'paper.pdf')
        File.write(path, '%PDF fake')
        result = parser.parse(file_path: path)
        expect(result.first[:error]).to eq('unsupported format')
      end
    end

    context 'with Legion::Data::Extract available' do
      let(:extract_result) { { text: 'extracted document text', metadata: { type: :pdf } } }
      let(:extractor) do
        mod = Module.new { def self.extract(*); end }
        allow(mod).to receive(:extract).and_return(extract_result)
        mod
      end

      before { stub_const('Legion::Data::Extract', extractor) }

      it 'delegates .pdf to Data::Extract' do
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'paper.pdf')
          File.write(path, '%PDF fake')
          parser.parse(file_path: path)
          expect(extractor).to have_received(:extract).with(path, type: :auto)
        end
      end

      it 'returns a single section with extracted content for .pdf' do
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'paper.pdf')
          File.write(path, '%PDF fake')
          result = parser.parse(file_path: path)
          expect(result.size).to eq(1)
          expect(result.first[:content]).to eq('extracted document text')
        end
      end

      it 'uses the filename (without extension) as heading' do
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'paper.pdf')
          File.write(path, '%PDF fake')
          result = parser.parse(file_path: path)
          expect(result.first[:heading]).to eq('paper')
        end
      end

      it 'sets section_path to an empty array' do
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'paper.pdf')
          File.write(path, '%PDF fake')
          result = parser.parse(file_path: path)
          expect(result.first[:section_path]).to eq([])
        end
      end

      it 'returns extraction_failed when Extract returns no :text key' do
        allow(extractor).to receive(:extract).and_return({ error: 'parse error' })
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'paper.pdf')
          File.write(path, '%PDF fake')
          result = parser.parse(file_path: path)
          expect(result.first[:error]).to eq('extraction_failed')
          expect(result.first[:detail]).to eq({ error: 'parse error' })
        end
      end

      it 'delegates .docx to Data::Extract' do
        allow(extractor).to receive(:extract).and_return({ text: 'docx content', metadata: {} })
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'report.docx')
          File.write(path, 'binary')
          result = parser.parse(file_path: path)
          expect(result.first[:content]).to eq('docx content')
        end
      end
    end
  end

  describe '.parse_markdown — heading depth' do
    it 'creates a 3-element section_path for ### headings under ## under #' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'arch.md')
        File.write(path, "# Architecture\n## Boot Sequence\n### Phase Handlers\nContent here\n")
        result = parser.parse_markdown(file_path: path)
        deep = result.find { |s| s[:heading] == 'Phase Handlers' }
        expect(deep[:section_path]).to eq(['Architecture', 'Boot Sequence', 'Phase Handlers'])
      end
    end

    it 'resets sub-path correctly when returning to a shallower level' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'doc.md')
        File.write(path, "# Top\n## Sub\n### Deep\nDeep content\n## Back\nBack content\n")
        result = parser.parse_markdown(file_path: path)
        back = result.find { |s| s[:heading] == 'Back' }
        expect(back[:section_path]).to eq(%w[Top Back])
      end
    end

    it 'handles a document starting with ### (no # or ##)' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'deep.md')
        File.write(path, "### Orphan Section\nContent\n")
        result = parser.parse_markdown(file_path: path)
        expect(result.first[:section_path]).to eq(['Orphan Section'])
      end
    end

    it 'handles #### (four-level depth)' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'deep4.md')
        File.write(path, "# A\n## B\n### C\n#### D\nContent\n")
        result = parser.parse_markdown(file_path: path)
        d = result.find { |s| s[:heading] == 'D' }
        expect(d[:section_path]).to eq(%w[A B C D])
      end
    end
  end
end
