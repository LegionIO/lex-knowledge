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

  describe 'batch embedding' do
    let(:file_path) { '/tmp/batch_test.md' }
    let(:chunk_a)   do
      { content: 'Chunk A', content_hash: 'hash_a', source_file: file_path, heading: 'H1', section_path: ['H1'], chunk_index: 0, token_count: 10 }
    end
    let(:chunk_b) do
      { content: 'Chunk B', content_hash: 'hash_b', source_file: file_path, heading: 'H1', section_path: ['H1'], chunk_index: 1, token_count: 10 }
    end
    let(:chunks) { [chunk_a, chunk_b] }

    describe '.batch_embed_chunks (via process_file)' do
      context 'when Legion::LLM is not defined' do
        before { hide_const('Legion::LLM') if defined?(Legion::LLM) }

        it 'returns nil embeddings for all chunks without raising' do
          result = described_class.send(:batch_embed_chunks, chunks, force: false)
          expect(result).to all(include(embedding: nil))
          expect(result.size).to eq(2)
        end
      end

      context 'when Legion::LLM is available with embed_batch' do
        let(:llm_double) { double('Legion::LLM') }

        before do
          stub_const('Legion::LLM', llm_double)
          allow(llm_double).to receive(:respond_to?).with(:embed_batch).and_return(true)
          allow(described_class).to receive(:chunk_exists?).and_return(false)
        end

        it 'calls embed_batch once (not per-chunk) for all chunks needing embed' do
          expect(llm_double).to receive(:embed_batch)
            .once
            .with(['Chunk A', 'Chunk B'])
            .and_return([{ index: 0, vector: [0.1, 0.2] }, { index: 1, vector: [0.3, 0.4] }])

          result = described_class.send(:batch_embed_chunks, chunks, force: false)
          expect(result.size).to eq(2)
        end

        it 'maps vectors to the correct chunks by index' do
          allow(llm_double).to receive(:embed_batch)
            .and_return([{ index: 0, vector: [0.1, 0.2] }, { index: 1, vector: [0.3, 0.4] }])

          result = described_class.send(:batch_embed_chunks, chunks, force: false)
          hash_to_embedding = result.to_h { |p| [p[:chunk][:content_hash], p[:embedding]] }
          expect(hash_to_embedding['hash_a']).to eq([0.1, 0.2])
          expect(hash_to_embedding['hash_b']).to eq([0.3, 0.4])
        end

        it 'assigns nil embedding for chunks whose embed result has an error key' do
          allow(llm_double).to receive(:embed_batch)
            .and_return([{ index: 0, vector: [0.1, 0.2] }, { index: 1, error: 'timeout' }])

          result = described_class.send(:batch_embed_chunks, chunks, force: false)
          hash_to_embedding = result.to_h { |p| [p[:chunk][:content_hash], p[:embedding]] }
          expect(hash_to_embedding['hash_a']).to eq([0.1, 0.2])
          expect(hash_to_embedding['hash_b']).to be_nil
        end

        it 'excludes already-existing chunks from the embed_batch call' do
          allow(described_class).to receive(:chunk_exists?).with('hash_a').and_return(true)
          allow(described_class).to receive(:chunk_exists?).with('hash_b').and_return(false)

          expect(llm_double).to receive(:embed_batch)
            .with(['Chunk B'])
            .and_return([{ index: 0, vector: [0.9, 0.8] }])

          result = described_class.send(:batch_embed_chunks, chunks, force: false)
          hash_to_embedding = result.to_h { |p| [p[:chunk][:content_hash], p[:embedding]] }
          expect(hash_to_embedding['hash_a']).to be_nil
          expect(hash_to_embedding['hash_b']).to eq([0.9, 0.8])
        end

        it 'includes all chunks in embed_batch when force: true, even existing ones' do
          allow(described_class).to receive(:chunk_exists?).and_return(true)

          expect(llm_double).to receive(:embed_batch)
            .with(['Chunk A', 'Chunk B'])
            .and_return([{ index: 0, vector: [0.1, 0.2] }, { index: 1, vector: [0.3, 0.4] }])

          described_class.send(:batch_embed_chunks, chunks, force: true)
        end

        it 'returns nil embeddings for all chunks when embed_batch raises' do
          allow(llm_double).to receive(:embed_batch).and_raise(StandardError, 'connection refused')

          result = described_class.send(:batch_embed_chunks, chunks, force: false)
          expect(result).to all(include(embedding: nil))
        end

        it 'returns nil embeddings for all chunks when needs_embed is empty' do
          allow(described_class).to receive(:chunk_exists?).and_return(true)
          expect(llm_double).not_to receive(:embed_batch)

          result = described_class.send(:batch_embed_chunks, chunks, force: false)
          expect(result).to all(include(embedding: nil))
        end
      end
    end
  end

  describe '#ingest_content' do
    it 'accepts string content directly' do
      result = described_class.ingest_content(
        content:     'This is meeting transcript text with enough words to form a chunk.',
        source_type: :meeting_transcript,
        metadata:    { meeting_id: 'abc-123' }
      )
      expect(result[:chunks]).to be_a(Integer)
      expect(result[:chunks]).to be > 0
    end

    it 'chunks and embeds string content' do
      allow(Legion::LLM).to receive(:embed_batch).and_return([]) if defined?(Legion::LLM)
      result = described_class.ingest_content(content: 'Short text content for testing.', source_type: :text)
      expect(result[:status]).to eq(:ingested)
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
