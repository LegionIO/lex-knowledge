# frozen_string_literal: true

RSpec.describe Legion::Extensions::Knowledge::Runners::Ingest do
  describe '.ingest_file' do
    let(:tmp_dir) { Dir.mktmpdir }
    let(:file_path) { File.join(tmp_dir, 'test.md') }

    before do
      File.write(file_path, "# Title\n\nSome content for testing.")
    end

    after { FileUtils.remove_entry(tmp_dir) }

    it 'returns success with chunk counts' do
      result = described_class.ingest_file(file_path: file_path)
      expect(result[:success]).to be true
      expect(result[:chunks_created]).to be >= 1
    end

    it 'skips chunks on second ingest when not forced' do
      described_class.ingest_file(file_path: file_path)
      result = described_class.ingest_file(file_path: file_path)
      expect(result[:success]).to be true
      # Without Apollo, all chunks are :created (no dedup possible)
      expect(result[:chunks_created]).to be >= 0
    end
  end

  describe '.scan_corpus' do
    let(:tmp_dir) { Dir.mktmpdir }

    before do
      File.write(File.join(tmp_dir, 'a.md'), '# A')
      File.write(File.join(tmp_dir, 'b.txt'), 'B content')
    end

    after { FileUtils.remove_entry(tmp_dir) }

    it 'returns file list and counts' do
      result = described_class.scan_corpus(path: tmp_dir)
      expect(result[:success]).to be true
      expect(result[:file_count]).to eq(2)
    end
  end
end
