# Changelog

## [0.4.0] - 2026-03-26

### Changed
- Batch embedding in ingest pipeline: `process_file` now calls `Legion::LLM.embed_batch` once per file instead of one embed call per chunk, reducing API round-trips significantly
- Added `batch_embed_chunks` and `upsert_chunk_with_embedding` private methods to support batched ingest path
- Graceful fallback: if `embed_batch` fails or LLM is unavailable, chunks ingest without embeddings (closes #2)

## [0.3.0] - 2026-03-26

### Added
- `Helpers::ManifestStore`: JSON sidecar persistence for corpus manifests (`~/.legionio/knowledge/<hash>.manifest.json`). Atomic writes (write `.tmp` then rename), graceful fallback to `[]` on error.
- `Runners::Corpus#manifest_path`: exposes the sidecar file path for CLI introspection
- PDF and DOCX parsing via `Legion::Data::Extract` when available; falls back to `{ error: 'unsupported format' }` when absent
- Markdown heading depth expanded from H1/H2 to full H1–H6 with correct ancestry stack (`section_path` now tracks full parent chain)

### Changed
- `Runners::Ingest#ingest_corpus` is now delta-driven: loads previous manifest, diffs against current scan, and only processes added/changed files. Removed files trigger a soft-delete signal to Apollo. `force: true` bypasses delta and processes all files. `dry_run: true` skips manifest persistence.
- Response hash from `ingest_corpus` now includes `files_added`, `files_changed`, `files_removed` in addition to chunk counts

## [0.2.0] - 2026-03-24

### Added
- Transport layer: knowledge exchange, ingest queue, ingest message
- CorpusWatcher actor: interval-based corpus re-ingestion (configurable via `knowledge.actors.watcher_interval`)
- CorpusIngest subscription actor: AMQP-based file ingestion
- `corpus_stats` implementation: file count, chunk estimate, total bytes
- Integration specs: end-to-end scan->parse->chunk->ingest pipeline

### Fixed
- `chunk_exists?` now queries Apollo data model directly instead of passing unsupported kwargs
- `generate_embedding` uses `Legion::LLM.embed` with correct return value extraction

## [0.1.1] - 2026-03-24

### Added
- GitHub Actions CI workflow (reusable workflows from LegionIO/.github)

## [0.1.0] - 2026-03-24

### Added
- Initial release: corpus scanner, markdown/text parser, token-aware chunker
- Ingest pipeline writes document chunks to Apollo as knowledge entries
- Query runner with optional LLM synthesis over retrieved chunks
