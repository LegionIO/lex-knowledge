# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions::Knowledge::Helpers::Chunker do
  subject(:chunker) { described_class }

  let(:section) do
    {
      heading:      'Introduction',
      section_path: ['Introduction'],
      source_file:  '/docs/guide.md',
      content:      "First paragraph of text.\n\nSecond paragraph with more detail.\n\nThird paragraph closing out the section."
    }
  end

  describe '.chunk' do
    it 'returns an array of chunk hashes' do
      result = chunker.chunk(sections: [section])
      expect(result).to be_an(Array)
      expect(result).not_to be_empty
    end

    it 'each chunk has the required keys' do
      result = chunker.chunk(sections: [section])
      result.each do |chunk|
        expect(chunk).to include(:content, :heading, :section_path, :source_file, :token_count, :chunk_index, :content_hash)
      end
    end

    it 'preserves heading and source_file from the section' do
      result = chunker.chunk(sections: [section])
      expect(result.first[:heading]).to eq('Introduction')
      expect(result.first[:source_file]).to eq('/docs/guide.md')
    end

    it 'computes a sha256 content_hash for each chunk' do
      result = chunker.chunk(sections: [section])
      result.each do |chunk|
        expect(chunk[:content_hash]).to match(/\A[0-9a-f]{64}\z/)
      end
    end

    it 'assigns sequential chunk_index values starting at 0' do
      long_content = Array.new(20) { |i| "Paragraph number #{i} with some filler text to exceed the token limit." }.join("\n\n")
      big_section  = section.merge(content: long_content)
      result       = chunker.chunk(sections: [big_section], max_tokens: 30)
      indices      = result.map { |c| c[:chunk_index] }
      expect(indices.first).to eq(0)
      expect(indices).to eq(indices.sort)
    end

    it 'keeps chunks within the max_tokens budget (character proxy)' do
      max_tokens = 20
      result     = chunker.chunk(sections: [section], max_tokens: max_tokens)
      max_chars  = max_tokens * 4
      result.each do |chunk|
        expect(chunk[:content].length).to be <= max_chars
      end
    end

    it 'handles an empty sections array' do
      result = chunker.chunk(sections: [])
      expect(result).to eq([])
    end

    it 'processes multiple sections in order' do
      sections = [
        section,
        section.merge(heading: 'Conclusion', content: 'Final thoughts.')
      ]
      result = chunker.chunk(sections: sections)
      headings = result.map { |c| c[:heading] }
      expect(headings).to include('Introduction', 'Conclusion')
    end

    it 'produces a non-zero token_count for each chunk' do
      result = chunker.chunk(sections: [section])
      result.each do |chunk|
        expect(chunk[:token_count]).to be > 0
      end
    end
  end
end
