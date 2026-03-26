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
