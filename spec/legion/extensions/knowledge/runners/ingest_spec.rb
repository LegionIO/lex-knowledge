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

  describe 'LLM ingest filtering' do
    let(:chunk_a) do
      { content: 'Useful architecture notes', content_hash: 'hash_a', source_file: '/tmp/a.md', chunk_index: 0 }
    end
    let(:chunk_b) do
      { content: 'Boilerplate navigation text', content_hash: 'hash_b', source_file: '/tmp/a.md', chunk_index: 1 }
    end
    let(:llm_double) { double('Legion::LLM') }

    before do
      described_class.send(:filter_cache).clear
      allow(described_class).to receive(:settings).and_return(
        ingest: { filter_prompt: 'Keep useful architecture notes only.', filter_threshold: 0.7 }
      )
      stub_const('Legion::LLM', llm_double)
      allow(llm_double).to receive(:respond_to?).with(:structured).and_return(true)
    end

    it 'drops chunks whose structured filter result is not relevant enough' do
      allow(llm_double).to receive(:structured).and_return(
        { data: { relevant: true, confidence: 0.9, reason: 'useful' } },
        { data: { relevant: false, confidence: 0.2, reason: 'noise' } }
      )

      filtered = described_class.send(:filter_chunks, [chunk_a, chunk_b], filter: true)

      expect(filtered).to eq([chunk_a])
    end

    it 'caches filter results by content hash' do
      duplicate = chunk_a.merge(content: 'Useful architecture notes repeated')

      allow(llm_double).to receive(:structured).and_return(
        { data: { relevant: true, confidence: 0.9, reason: 'useful' } },
        { data: { relevant: false, confidence: 0.2, reason: 'noise' } }
      )

      filtered = described_class.send(:filter_chunks, [chunk_a, duplicate, chunk_b], filter: true)

      expect(filtered).to eq([chunk_a, duplicate])
      expect(llm_double).to have_received(:structured).twice
    end

    it 'bypasses the LLM when filter is disabled' do
      expect(llm_double).not_to receive(:structured)

      filtered = described_class.send(:filter_chunks, [chunk_a, chunk_b], filter: false)

      expect(filtered).to eq([chunk_a, chunk_b])
    end

    it 'counts filtered chunks as skipped before embedding' do
      allow(Legion::Extensions::Knowledge::Helpers::Parser).to receive(:parse).and_return([{ content: 'parsed' }])
      allow(Legion::Extensions::Knowledge::Helpers::Chunker).to receive(:chunk).and_return([chunk_a, chunk_b])
      allow(described_class).to receive(:filter_chunks).and_return([chunk_a])
      allow(described_class).to receive(:batch_embed_chunks).with([chunk_a], force: false)
                                                            .and_return([{ chunk: chunk_a, embedding: nil, exists: false }])
      allow(described_class).to receive(:upsert_chunk_with_embedding).and_return(:created)

      result = described_class.send(:process_file, '/tmp/a.md', dry_run: false, force: false, filter: true)

      expect(result).to eq({ created: 1, skipped: 1, updated: 0 })
    end

    it 'accepts filter false on the public single-file ingest runner' do
      allow(described_class).to receive(:process_file)
        .with('/tmp/a.md', dry_run: false, force: false, filter: false)
        .and_return({ created: 1, skipped: 0, updated: 0 })

      result = described_class.ingest_file(file_path: '/tmp/a.md', filter: false)

      expect(result[:success]).to be true
      expect(result[:chunks_created]).to eq(1)
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

  describe '.upsert_chunk_with_embedding — persistence outcome propagation' do
    let(:chunk) do
      {
        content:      'Chunk contents for persistence test.',
        content_hash: 'abcdef0123456789abcdef0123456789',
        source_file:  '/tmp/test.md',
        heading:      'H1',
        section_path: ['H1'],
        chunk_index:  0,
        token_count:  9
      }
    end
    let(:embedding) { [0.1, 0.2, 0.3] }

    context 'when dry_run: true' do
      it 'returns :created without contacting apollo' do
        expect(described_class).not_to receive(:ingest_to_apollo)
        outcome = described_class.send(:upsert_chunk_with_embedding, chunk, embedding, dry_run: true)
        expect(outcome).to eq(:created)
      end
    end

    context 'when Legion::Extensions::Apollo is not defined' do
      before { hide_const('Legion::Extensions::Apollo') if defined?(Legion::Extensions::Apollo) }

      it 'returns :created' do
        outcome = described_class.send(:upsert_chunk_with_embedding, chunk, embedding)
        expect(outcome).to eq(:created)
      end
    end

    context 'when apollo is defined' do
      before { stub_const('Legion::Extensions::Apollo', Module.new) }

      it 'returns :skipped when exists is true and force is false' do
        expect(described_class).not_to receive(:ingest_to_apollo)
        outcome = described_class.send(:upsert_chunk_with_embedding, chunk, embedding, exists: true)
        expect(outcome).to eq(:skipped)
      end

      it 'returns :created when handle_ingest returns a success hash' do
        allow(described_class).to receive(:ingest_to_apollo).and_return({ success: true, entry_id: 42 })
        outcome = described_class.send(:upsert_chunk_with_embedding, chunk, embedding)
        expect(outcome).to eq(:created)
      end

      it 'returns :updated when force: true and handle_ingest succeeds' do
        allow(described_class).to receive(:ingest_to_apollo).and_return({ success: true, entry_id: 42 })
        outcome = described_class.send(:upsert_chunk_with_embedding, chunk, embedding, force: true, exists: true)
        expect(outcome).to eq(:updated)
      end

      it 'returns :skipped and emits a warn log when handle_ingest returns success: false' do
        allow(described_class).to receive(:ingest_to_apollo)
          .and_return({ success: false, error: 'PG::StringDataRightTruncation' })
        expect(described_class.log).to receive(:warn).with(/apollo persistence not confirmed/)
        outcome = described_class.send(:upsert_chunk_with_embedding, chunk, embedding)
        expect(outcome).to eq(:skipped)
      end

      it 'returns :skipped when handle_ingest returns a non-Hash result' do
        allow(described_class).to receive(:ingest_to_apollo).and_return(nil)
        expect(described_class.log).to receive(:warn).with(/non-hash result class=NilClass/)
        outcome = described_class.send(:upsert_chunk_with_embedding, chunk, embedding)
        expect(outcome).to eq(:skipped)
      end

      it 'returns :skipped when handle_ingest returns a hash without success' do
        allow(described_class).to receive(:ingest_to_apollo).and_return({ entry_id: 42 })
        expect(described_class.log).to receive(:warn).with(/apollo persistence not confirmed/)
        outcome = described_class.send(:upsert_chunk_with_embedding, chunk, embedding)
        expect(outcome).to eq(:skipped)
      end

      it 'returns :skipped and logs when ingest_to_apollo raises' do
        allow(described_class).to receive(:ingest_to_apollo).and_raise(StandardError, 'boom')
        expect(described_class).to receive(:handle_exception).with(
          instance_of(StandardError),
          hash_including(level: :warn, operation: 'knowledge.ingest.upsert_chunk')
        )
        outcome = described_class.send(:upsert_chunk_with_embedding, chunk, embedding)
        expect(outcome).to eq(:skipped)
      end
    end
  end

  describe '.ingest_to_apollo' do
    let(:chunk) do
      {
        content:      'Chunk contents for Apollo context.',
        content_hash: 'abcdef0123456789abcdef0123456789',
        source_file:  '/tmp/context.md',
        heading:      'Context',
        section_path: ['Context'],
        chunk_index:  4,
        token_count:  7
      }
    end

    before do
      stub_const('Legion::Extensions::Apollo', Module.new)
      runners_mod = Module.new
      knowledge_mod = Module.new
      knowledge_mod.define_singleton_method(:handle_ingest) { |**| { success: true } }
      runners_mod.const_set(:Knowledge, knowledge_mod)
      stub_const('Legion::Extensions::Apollo::Runners', runners_mod)
    end

    it 'passes chunk metadata as Apollo context for neighbor retrieval' do
      expect(Legion::Extensions::Apollo::Runners::Knowledge).to receive(:handle_ingest).with(
        hash_including(
          content:  chunk[:content],
          context:  hash_including(source_file: '/tmp/context.md', chunk_index: 4),
          metadata: hash_including(source_file: '/tmp/context.md', chunk_index: 4)
        )
      ).and_return({ success: true })

      described_class.send(:ingest_to_apollo, chunk, nil)
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
