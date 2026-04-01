# Changelog

## [0.6.5] - 2026-03-31

### Fixed
- `chunk_exists?` uses cross-DB `Sequel.like` instead of PostgreSQL-only `pg_array_op`

## [0.6.4] - 2026-03-30

### Changed
- update to rubocop-legion 0.1.7, resolve all offenses

## [0.6.3] - 2026-03-28

### Fixed
- `CorpusWatcher` and `MaintenanceRunner` actors now override `time` instead of `every_interval` — the `Every` actor base class uses `time` for `Concurrent::TimerTask` interval, causing both actors to fire every 1 second instead of 300s/21600s

## [Unreleased]

### Added
- `Runners::Ingest#ingest_content` — accepts string content directly for network absorbers, skips file extraction
- `Runners::Monitor` module for multi-directory corpus management
- `add_monitor`, `remove_monitor`, `list_monitors`, `monitor_status`, `resolve_monitors` runner methods
- `MonitorReload` transport message (`knowledge.monitor.reload`) for hot-reload signaling
- `CorpusWatcher` now iterates `monitors[]` array instead of single `corpus_path`

### Changed
- `ingest_corpus` accepts optional `monitors:` kwarg for batch multi-path ingestion
- `CorpusWatcher#enabled?` uses `Runners::Monitor.resolve_monitors` (backwards compat with legacy `corpus_path`)

## [0.6.1] - 2026-03-26

### Changed
- set remote_invocable? false for local dispatch

## [0.5.0] - 2026-03-26

### Added
- `Runners::Maintenance` module: `detect_orphans`, `cleanup_orphans`, `reindex`, `health`, `quality_report`
- `Runners::Query#record_feedback` for explicit quality feedback with SHA256 question hashing
- Enriched response metadata in `query()` and `retrieve()`: confidence_avg, confidence_range, distance_range, source_files, source_file_count, all_embedded, statuses
- Implicit feedback tracking: `query()` auto-records feedback after successful retrieval
- `Actor::MaintenanceRunner`: periodic health check actor (6-hour default interval)
- `quality_report` surfaces hot chunks, cold chunks, low-confidence chunks, and summary stats

### Changed
- `query()` metadata hash now includes 7 additional fields (backwards-compatible addition)
- `retrieve()` metadata hash now matches `query()` structure (minus latency_ms)

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
