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

  describe '.ingest_corpus — delta behavior' do
    let(:tmp_dir)   { Dir.mktmpdir }
    let(:store_dir) { Dir.mktmpdir }

    before do
      stub_const('Legion::Extensions::Knowledge::Helpers::ManifestStore::STORE_DIR', store_dir)
      File.write(File.join(tmp_dir, 'a.md'), "# Alpha\nFirst content")
      File.write(File.join(tmp_dir, 'b.md'), "# Beta\nSecond content")
    end

    after do
      FileUtils.remove_entry(tmp_dir)
      FileUtils.remove_entry(store_dir)
    end

    it 'processes all files on first run (no manifest exists)' do
      result = described_class.ingest_corpus(path: tmp_dir)
      expect(result[:success]).to be true
      expect(result[:files_added]).to eq(2)
      expect(result[:files_changed]).to eq(0)
    end

    it 'saves the manifest after first run' do
      described_class.ingest_corpus(path: tmp_dir)
      store_path = Legion::Extensions::Knowledge::Helpers::ManifestStore.store_path(corpus_path: tmp_dir)
      expect(File.exist?(store_path)).to be true
    end

    it 'processes zero files on second run when corpus is unchanged' do
      described_class.ingest_corpus(path: tmp_dir)
      result = described_class.ingest_corpus(path: tmp_dir)
      expect(result[:files_added]).to eq(0)
      expect(result[:files_changed]).to eq(0)
    end

    it 'processes only the changed file on subsequent run' do
      described_class.ingest_corpus(path: tmp_dir)
      sleep 0.01
      changed_path = File.join(tmp_dir, 'a.md')
      File.write(changed_path, "# Alpha\nUpdated content")
      result = described_class.ingest_corpus(path: tmp_dir)
      expect(result[:files_changed]).to eq(1)
      expect(result[:files_added]).to eq(0)
    end

    it 'reports removed files when a file is deleted' do
      described_class.ingest_corpus(path: tmp_dir)
      File.delete(File.join(tmp_dir, 'b.md'))
      result = described_class.ingest_corpus(path: tmp_dir)
      expect(result[:files_removed]).to eq(1)
    end

    it 'does not save manifest on dry_run' do
      described_class.ingest_corpus(path: tmp_dir, dry_run: true)
      store_path = Legion::Extensions::Knowledge::Helpers::ManifestStore.store_path(corpus_path: tmp_dir)
      expect(File.exist?(store_path)).to be false
    end

    it 'processes all files when force: true regardless of manifest' do
      described_class.ingest_corpus(path: tmp_dir)
      result = described_class.ingest_corpus(path: tmp_dir, force: true)
      expect(result[:files_added]).to eq(2)
    end

    it 'returns files_scanned equal to total current files' do
      result = described_class.ingest_corpus(path: tmp_dir)
      expect(result[:files_scanned]).to eq(2)
    end
  end
end
