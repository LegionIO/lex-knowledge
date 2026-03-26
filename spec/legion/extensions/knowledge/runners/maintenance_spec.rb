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

  describe '.health' do
    context 'when no manifest has been built yet' do
      it 'returns a hash with :local, :apollo, and :sync top-level keys' do
        result = described_class.health(path: tmp_dir)
        expect(result[:success]).to be true
        expect(result).to include(:local, :apollo, :sync)
      end

      it 'includes corpus_path in the local section' do
        result = described_class.health(path: tmp_dir)
        expect(result[:local][:corpus_path]).to eq(tmp_dir)
      end

      it 'reports file_count from filesystem scan' do
        result = described_class.health(path: tmp_dir)
        expect(result[:local][:file_count]).to eq(2)
      end

      it 'reports total_bytes as positive integer from scan' do
        result = described_class.health(path: tmp_dir)
        expect(result[:local][:total_bytes]).to be_a(Integer)
        expect(result[:local][:total_bytes]).to be > 0
      end

      it 'reports manifest_exists as false when no manifest sidecar exists' do
        result = described_class.health(path: tmp_dir)
        expect(result[:local][:manifest_exists]).to be false
      end

      it 'reports last_ingest as nil when no manifest sidecar exists' do
        result = described_class.health(path: tmp_dir)
        expect(result[:local][:last_ingest]).to be_nil
      end
    end

    context 'when a manifest has been built via ingest_corpus' do
      before { Legion::Extensions::Knowledge::Runners::Ingest.ingest_corpus(path: tmp_dir) }

      it 'reports manifest_exists as true' do
        result = described_class.health(path: tmp_dir)
        expect(result[:local][:manifest_exists]).to be true
      end

      it 'reports last_ingest as an ISO 8601 string' do
        result = described_class.health(path: tmp_dir)
        expect(result[:local][:last_ingest]).to be_a(String)
        expect(result[:local][:last_ingest]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
      end
    end

    context 'Apollo section when Legion::Data::Model::ApolloEntry is not defined' do
      it 'returns total_chunks of 0' do
        result = described_class.health(path: tmp_dir)
        expect(result[:apollo][:total_chunks]).to eq(0)
      end

      it 'returns embedding_coverage of 0.0' do
        result = described_class.health(path: tmp_dir)
        expect(result[:apollo][:embedding_coverage]).to eq(0.0)
      end

      it 'returns avg_confidence of 0.0' do
        result = described_class.health(path: tmp_dir)
        expect(result[:apollo][:avg_confidence]).to eq(0.0)
      end

      it 'returns empty by_status hash' do
        result = described_class.health(path: tmp_dir)
        expect(result[:apollo][:by_status]).to eq({})
      end

      it 'returns stale_count of 0' do
        result = described_class.health(path: tmp_dir)
        expect(result[:apollo][:stale_count]).to eq(0)
      end

      it 'returns never_accessed of 0' do
        result = described_class.health(path: tmp_dir)
        expect(result[:apollo][:never_accessed]).to eq(0)
      end

      it 'returns unique_source_files of 0' do
        result = described_class.health(path: tmp_dir)
        expect(result[:apollo][:unique_source_files]).to eq(0)
      end

      it 'returns nil oldest_chunk and newest_chunk' do
        result = described_class.health(path: tmp_dir)
        expect(result[:apollo][:oldest_chunk]).to be_nil
        expect(result[:apollo][:newest_chunk]).to be_nil
      end

      it 'returns confidence_range as [0.0, 0.0]' do
        result = described_class.health(path: tmp_dir)
        expect(result[:apollo][:confidence_range]).to eq([0.0, 0.0])
      end
    end

    context 'sync section' do
      before { Legion::Extensions::Knowledge::Runners::Ingest.ingest_corpus(path: tmp_dir) }

      it 'includes orphan_count and missing_count keys' do
        result = described_class.health(path: tmp_dir)
        expect(result[:sync]).to include(:orphan_count, :missing_count)
      end

      it 'reports orphan_count of 0 when Apollo is unavailable' do
        result = described_class.health(path: tmp_dir)
        expect(result[:sync][:orphan_count]).to eq(0)
      end

      it 'reports missing_count equal to manifest file count when Apollo has no entries' do
        result = described_class.health(path: tmp_dir)
        expect(result[:sync][:missing_count]).to eq(2)
      end
    end

    context 'error handling' do
      it 'returns success: false when an error is raised' do
        allow(Legion::Extensions::Knowledge::Helpers::Manifest).to receive(:scan).and_raise(RuntimeError, 'boom')
        result = described_class.health(path: tmp_dir)
        expect(result[:success]).to be false
        expect(result[:error]).to eq('boom')
      end
    end
  end
end
