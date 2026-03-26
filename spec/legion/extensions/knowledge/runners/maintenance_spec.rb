# frozen_string_literal: true

RSpec.describe Legion::Extensions::Knowledge::Runners::Maintenance do
  let(:tmp_dir)   { Dir.mktmpdir }
  let(:store_dir) { Dir.mktmpdir }

  before do
    stub_const('Legion::Extensions::Knowledge::Helpers::ManifestStore::STORE_DIR', store_dir)
    File.write(File.join(tmp_dir, 'alpha.md'), "# Alpha\n\nFirst document content.")
    File.write(File.join(tmp_dir, 'beta.md'),  "# Beta\n\nSecond document content.")
  end

  after do
    FileUtils.remove_entry(tmp_dir)
    FileUtils.remove_entry(store_dir)
  end

  describe '.detect_orphans' do
    context 'when manifest has been built via ingest_corpus' do
      before { Legion::Extensions::Knowledge::Runners::Ingest.ingest_corpus(path: tmp_dir) }

      it 'returns a success hash with all required keys' do
        result = described_class.detect_orphans(path: tmp_dir)
        expect(result[:success]).to be true
        expect(result).to include(:orphan_count, :orphan_files, :total_manifest_files, :total_apollo_chunks)
      end

      it 'reports orphan_count as zero when Apollo is unavailable (no DB = no Apollo files)' do
        result = described_class.detect_orphans(path: tmp_dir)
        expect(result[:orphan_count]).to eq(0)
        expect(result[:orphan_files]).to be_empty
      end

      it 'reports total_manifest_files equal to the number of ingested files' do
        result = described_class.detect_orphans(path: tmp_dir)
        expect(result[:total_manifest_files]).to eq(2)
      end

      it 'reports total_apollo_chunks as zero when Legion::Data::Model::ApolloEntry is not defined' do
        result = described_class.detect_orphans(path: tmp_dir)
        expect(result[:total_apollo_chunks]).to eq(0)
      end
    end

    context 'when no manifest exists yet' do
      it 'returns success with total_manifest_files of zero' do
        result = described_class.detect_orphans(path: tmp_dir)
        expect(result[:success]).to be true
        expect(result[:total_manifest_files]).to eq(0)
      end

      it 'returns zero orphans when both manifest and Apollo are empty' do
        result = described_class.detect_orphans(path: tmp_dir)
        expect(result[:orphan_count]).to eq(0)
        expect(result[:orphan_files]).to be_empty
      end
    end

    context 'when Apollo reports source files not in the manifest' do
      before do
        Legion::Extensions::Knowledge::Runners::Ingest.ingest_corpus(path: tmp_dir)
        allow(described_class).to receive(:load_apollo_source_files)
          .and_return(['/gone/old_file.md', File.join(tmp_dir, 'alpha.md')])
      end

      it 'identifies files present in Apollo but absent from the manifest as orphans' do
        result = described_class.detect_orphans(path: tmp_dir)
        expect(result[:success]).to be true
        expect(result[:orphan_count]).to eq(1)
        expect(result[:orphan_files]).to include('/gone/old_file.md')
      end
    end
  end

  describe '.cleanup_orphans' do
    before { Legion::Extensions::Knowledge::Runners::Ingest.ingest_corpus(path: tmp_dir) }

    it 'defaults to dry_run: true' do
      result = described_class.cleanup_orphans(path: tmp_dir)
      expect(result[:success]).to be true
      expect(result[:dry_run]).to be true
    end

    it 'returns zero archived and files_cleaned when there are no orphans' do
      result = described_class.cleanup_orphans(path: tmp_dir)
      expect(result[:archived]).to eq(0)
      expect(result[:files_cleaned]).to eq(0)
    end

    context 'with orphans present (stubbed)' do
      before do
        allow(described_class).to receive(:load_apollo_source_files)
          .and_return(['/stale/a.md', '/stale/b.md'])
      end

      it 'returns dry_run: true and non-zero counts when dry_run is true' do
        result = described_class.cleanup_orphans(path: tmp_dir, dry_run: true)
        expect(result[:success]).to be true
        expect(result[:dry_run]).to be true
        expect(result[:archived]).to eq(2)
        expect(result[:files_cleaned]).to eq(2)
      end

      it 'returns dry_run: false and archived count when dry_run is false' do
        allow(described_class).to receive(:archive_orphan_entries).and_return(2)
        result = described_class.cleanup_orphans(path: tmp_dir, dry_run: false)
        expect(result[:success]).to be true
        expect(result[:dry_run]).to be false
        expect(result[:archived]).to eq(2)
        expect(result[:files_cleaned]).to eq(2)
      end
    end
  end

  describe '.reindex' do
    it 'deletes the manifest sidecar and re-ingests the corpus' do
      Legion::Extensions::Knowledge::Runners::Ingest.ingest_corpus(path: tmp_dir)

      store_path = Legion::Extensions::Knowledge::Helpers::ManifestStore.store_path(corpus_path: tmp_dir)
      expect(File.exist?(store_path)).to be true

      result = described_class.reindex(path: tmp_dir)
      expect(result[:success]).to be true
      expect(File.exist?(store_path)).to be true
    end

    it 'force-ingests all files even when the manifest previously had no changes' do
      Legion::Extensions::Knowledge::Runners::Ingest.ingest_corpus(path: tmp_dir)

      result = described_class.reindex(path: tmp_dir)
      expect(result[:success]).to be true
      expect(result[:files_added]).to eq(2)
    end

    it 'succeeds even when no prior manifest exists' do
      result = described_class.reindex(path: tmp_dir)
      expect(result[:success]).to be true
    end
  end
end
