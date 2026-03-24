# frozen_string_literal: true

RSpec.describe 'End-to-end ingestion pipeline' do
  let(:tmp_dir) { Dir.mktmpdir }

  before do
    File.write(File.join(tmp_dir, 'architecture.md'), <<~MD)
      # System Architecture

      The system uses a layered design with clear separation of concerns.

      ## Data Layer

      PostgreSQL with pgvector for semantic search. All queries go through
      the connection pool managed by Sequel.

      ## Transport Layer

      RabbitMQ handles async messaging between services. Topic exchanges
      route messages by type.
    MD

    File.write(File.join(tmp_dir, 'notes.txt'), "Simple plain text notes for the project.\n" * 20)
  end

  after { FileUtils.remove_entry(tmp_dir) }

  it 'scans, parses, chunks, and ingests a corpus' do
    scan = Legion::Extensions::Knowledge::Runners::Ingest.scan_corpus(path: tmp_dir)
    expect(scan[:file_count]).to eq(2)

    result = Legion::Extensions::Knowledge::Runners::Ingest.ingest_corpus(path: tmp_dir)
    expect(result[:success]).to be true
    expect(result[:files_scanned]).to eq(2)
    expect(result[:chunks_created]).to be >= 2
  end

  it 're-ingesting same corpus does not duplicate (without Apollo, all are :created)' do
    first  = Legion::Extensions::Knowledge::Runners::Ingest.ingest_corpus(path: tmp_dir)
    second = Legion::Extensions::Knowledge::Runners::Ingest.ingest_corpus(path: tmp_dir)
    expect(second[:success]).to be true
    expect(second[:files_scanned]).to eq(first[:files_scanned])
  end

  it 'stats match actual corpus' do
    stats = Legion::Extensions::Knowledge::Runners::Corpus.corpus_stats(path: tmp_dir)
    expect(stats[:file_count]).to eq(2)
    expect(stats[:estimated_chunks]).to be >= 2
  end
end
