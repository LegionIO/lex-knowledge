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

    it 'computes a 32-char (MD5-length) content_hash for each chunk' do
      # Keep chunk hashes aligned with Apollo Writeback and compatible with
      # older apollo_entries.content_hash columns fixed at MD5 length.
      result = chunker.chunk(sections: [section])
      result.each do |chunk|
        expect(chunk[:content_hash]).to match(/\A[0-9a-f]{32}\z/)
      end
    end

    it 'content_hash matches MD5 of whitespace-normalized content' do
      # Mirrors Apollo::Helpers::Writeback.content_hash semantics: strip, downcase,
      # collapse whitespace, then MD5. This keeps dedup consistent with apollo.
      result = chunker.chunk(sections: [section])
      result.each do |chunk|
        normalized = chunk[:content].to_s.strip.downcase.gsub(/\s+/, ' ')
        expect(chunk[:content_hash]).to eq(Digest::MD5.hexdigest(normalized))
      end
    end

    it 'delegates to Apollo::Helpers::Writeback.content_hash when defined' do
      writeback = Module.new do
        def self.content_hash(content)
          "apollo-#{Digest::MD5.hexdigest(content.to_s)}"[0, 32]
        end
      end
      stub_const('Legion::Extensions::Apollo::Helpers::Writeback', writeback)
      result = chunker.chunk(sections: [section])
      expected = writeback.content_hash(result.first[:content])
      expect(result.first[:content_hash]).to eq(expected)
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
