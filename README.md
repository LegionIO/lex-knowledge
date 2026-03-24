# lex-knowledge

Document corpus ingestion and knowledge query pipeline for LegionIO.

`lex-knowledge` walks a directory of documents, parses them into sections, splits sections into token-aware chunks, and writes each chunk to Apollo as a searchable knowledge entry. A query runner retrieves relevant chunks via semantic search and optionally synthesizes an answer through the LLM pipeline.

## Phase A: Corpus Ingestion

This gem implements Phase A of the knowledge pipeline:

- **Manifest**: file walker with SHA256 fingerprinting and incremental diff support
- **Parser**: section-aware extraction for Markdown and plain text
- **Chunker**: paragraph-respecting splits with configurable token budget and overlap
- **Ingest runners**: full corpus or single-file ingestion, writing chunks to Apollo
- **Query runners**: retrieval-only or retrieval + LLM synthesis

`.docx` and `.pdf` parsing are deferred to a later phase.

## Usage

```ruby
require 'legion/extensions/knowledge'

# Ingest an entire directory
Legion::Extensions::Knowledge::Runners::Ingest.ingest_corpus(
  path:    '/path/to/docs',
  dry_run: false,
  force:   false
)
# => { success: true, files_scanned: 12, chunks_created: 84, chunks_skipped: 0, chunks_updated: 0 }

# Ingest a single file
Legion::Extensions::Knowledge::Runners::Ingest.ingest_file(
  file_path: '/path/to/docs/guide.md'
)
# => { success: true, file: '...', chunks_created: 7, chunks_skipped: 0, chunks_updated: 0 }

# Query with LLM synthesis
Legion::Extensions::Knowledge::Runners::Query.query(
  question:   'How does Legion route tasks?',
  top_k:      5,
  synthesize: true
)
# => { success: true, answer: '...', sources: [...], metadata: { retrieval_score: 0.87, chunk_count: 5, latency_ms: 312 } }

# Retrieval only (no LLM)
Legion::Extensions::Knowledge::Runners::Query.retrieve(
  question: 'What is a LEX extension?',
  top_k:    3
)
# => { success: true, sources: [...], metadata: { chunk_count: 3 } }
```

## Configuration

Settings are read from `Legion::Settings` under the `:knowledge` key:

```yaml
knowledge:
  chunker:
    max_tokens: 512      # default 512
    overlap_tokens: 128  # default 128
  query:
    top_k: 5             # default 5
```

## Dependencies

- `legion-cache`, `legion-crypt`, `legion-data`, `legion-json`, `legion-logging`, `legion-settings`, `legion-transport`
- `lex-apollo` (optional): chunk storage and vector retrieval
- `legion-llm` (optional): answer synthesis

Both optional dependencies are guarded with `defined?()` — the gem degrades gracefully when they are absent.

## License

MIT
