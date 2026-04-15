# frozen_string_literal: true

RSpec.describe Legion::Extensions::Knowledge::Runners::Query do
  describe '.query metadata enrichment' do
    it 'includes enriched metadata keys' do
      result = described_class.query(question: 'test', synthesize: false)
      expect(result[:success]).to be true
      expect(result[:metadata]).to have_key(:confidence_avg)
      expect(result[:metadata]).to have_key(:confidence_range)
      expect(result[:metadata]).to have_key(:distance_range)
      expect(result[:metadata]).to have_key(:source_files)
      expect(result[:metadata]).to have_key(:source_file_count)
      expect(result[:metadata]).to have_key(:all_embedded)
      expect(result[:metadata]).to have_key(:statuses)
      expect(result[:metadata]).to have_key(:latency_ms)
    end

    it 'returns nil confidence_avg when no chunks retrieved' do
      result = described_class.query(question: 'nonexistent', synthesize: false)
      expect(result[:metadata][:confidence_avg]).to be_nil
    end

    it 'returns empty source_files when no chunks' do
      result = described_class.query(question: 'nonexistent', synthesize: false)
      expect(result[:metadata][:source_files]).to eq([])
      expect(result[:metadata][:source_file_count]).to eq(0)
    end

    it 'returns all_embedded true when no chunks' do
      result = described_class.query(question: 'x', synthesize: false)
      expect(result[:metadata][:all_embedded]).to be true
    end
  end

  describe '.retrieve metadata enrichment' do
    it 'includes enriched metadata keys' do
      result = described_class.retrieve(question: 'anything')
      expect(result[:success]).to be true
      expect(result[:metadata]).to have_key(:confidence_avg)
      expect(result[:metadata]).to have_key(:source_files)
    end

    it 'does not include latency_ms' do
      result = described_class.retrieve(question: 'x')
      expect(result[:metadata]).not_to have_key(:latency_ms)
    end
  end

  describe '.retrieve_chunks (via .query)' do
    context 'when retrieve_relevant returns a Hash (not an Array)' do
      before do
        stub_const('Legion::Extensions::Apollo', Module.new)
        runners_mod = Module.new
        knowledge_mod = Module.new
        knowledge_mod.define_singleton_method(:retrieve_relevant) do |**|
          { success: true, entries: [
            { id: 1, content: 'chunk text', content_type: 'document_chunk',
              confidence: 0.8, distance: 0.2, tags: [], source_agent: 'test',
              knowledge_domain: 'general' }
          ], count: 1 }
        end
        runners_mod.const_set(:Knowledge, knowledge_mod)
        stub_const('Legion::Extensions::Apollo::Runners', runners_mod)
      end

      it 'returns success without TypeError on query' do
        result = described_class.query(question: 'legion', synthesize: false)
        expect(result[:success]).to be true
      end

      it 'extracts entries array from retrieve_relevant Hash response' do
        result = described_class.query(question: 'legion', synthesize: false)
        expect(result[:sources]).to be_an(Array)
        expect(result[:sources].size).to eq(1)
      end

      it 'does not raise no implicit conversion of Symbol into Integer' do
        expect { described_class.query(question: 'legion', synthesize: false) }.not_to raise_error
      end
    end
  end

  describe '.record_feedback' do
    it 'returns success with question_hash' do
      result = described_class.record_feedback(
        question:        'test question',
        chunk_ids:       [],
        retrieval_score: 0.5,
        synthesized:     true
      )
      expect(result[:success]).to be true
      expect(result[:question_hash]).to be_a(String)
      expect(result[:question_hash].length).to eq(16)
    end

    it 'accepts optional rating' do
      result = described_class.record_feedback(
        question:        'test',
        chunk_ids:       [],
        retrieval_score: 0.4,
        synthesized:     false,
        rating:          :good
      )
      expect(result[:success]).to be true
      expect(result[:rating]).to eq(:good)
    end

    it 'returns deterministic question_hash' do
      h1 = described_class.record_feedback(question: 'same', chunk_ids: [], retrieval_score: 0.5)[:question_hash]
      h2 = described_class.record_feedback(question: 'same', chunk_ids: [], retrieval_score: 0.5)[:question_hash]
      expect(h1).to eq(h2)
    end
  end
end
