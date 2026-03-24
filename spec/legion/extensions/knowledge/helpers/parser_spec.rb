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

    it 'returns an unsupported format error for .docx files' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'report.docx')
        File.write(path, 'binary blob')
        result = parser.parse(file_path: path)
        expect(result.first[:error]).to eq('unsupported format')
      end
    end

    it 'returns an unsupported format error for .pdf files' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'paper.pdf')
        File.write(path, '%PDF fake')
        result = parser.parse(file_path: path)
        expect(result.first[:error]).to eq('unsupported format')
      end
    end
  end
end
