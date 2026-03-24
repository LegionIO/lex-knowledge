# frozen_string_literal: true

RSpec.describe Legion::Extensions::Knowledge::Runners::Corpus do
  describe '.corpus_stats' do
    let(:tmp_dir) { Dir.mktmpdir }

    before do
      File.write(File.join(tmp_dir, 'doc.md'), "# Title\n\nParagraph one.\n\nParagraph two.")
    end

    after { FileUtils.remove_entry(tmp_dir) }

    it 'returns file and chunk counts' do
      result = described_class.corpus_stats(path: tmp_dir)
      expect(result[:success]).to be true
      expect(result[:file_count]).to eq(1)
      expect(result[:estimated_chunks]).to be >= 1
    end

    it 'returns error for missing path' do
      result = described_class.corpus_stats(path: '/nonexistent/path')
      expect(result[:success]).to be false
    end
  end
end
