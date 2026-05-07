# Changelog

## [0.6.15] - 2026-05-07

### Fixed
- Knowledge ingest now sends Apollo chunk provenance through `context:` while retaining metadata compatibility, so source file, heading, section path, chunk index, and token count persist with document chunks.
- Batch embedding now falls back to per-chunk `Legion::LLM.embed` when `embed_batch` is unavailable.
- Retired corpus files now emit explicit observation entries tagged `retired` instead of using an Apollo-unknown `document_retired` content type.
- Retrieval and synthesis failures are logged through helper-based exception handling, and synthesis returns `nil` instead of presenting error strings as answers.
- Monitor-only installs now enable the maintenance actor without requiring `corpus_path`.
- Quality reports count Apollo query access logs with the `query` action recorded by lex-apollo.

## [0.6.14] - 2026-05-06

### Changed
- Knowledge defaults are now declared directly in `Knowledge.default_settings`, and helpers, runners, actors, and JSON sidecar persistence use Legion logging, settings, and JSON helpers end to end.

## [0.6.13] - 2026-05-06

### Added
- Knowledge ingest now supports optional LLM-based chunk filtering through `knowledge.ingest.filter_prompt`, with confidence thresholding, content-hash caching, and a runner-level `filter: false` bypass for no-filter ingest flows.

## [0.6.12] - 2026-05-06

### Added
- Query and retrieve runners now support optional neighbor expansion (`expand_neighbors: true`, `neighbor_radius:`) to include adjacent document chunks around Apollo retrieval hits.

### Fixed
- Knowledge ingest now sends chunk source metadata as Apollo `context` so `source_file` and `chunk_index` are available for neighbor retrieval.

## [0.6.11] - 2026-05-06

### Fixed
- Knowledge ingest and maintenance now resolve Apollo data models through the namespaced `Legion::Data::Model::Apollo::*` classes introduced by the legion-data schema cleanup, with fallback support for legacy Apollo model constants.

## [0.6.10] - 2026-04-28

### Fixed
- Chunker `content_hash` now uses MD5 + whitespace normalization (matching `Legion::Extensions::Apollo::Helpers::Writeback.content_hash`) instead of raw SHA-256. This keeps knowledge chunk deduplication aligned with Apollo writeback and avoids insert truncation on deployments whose `apollo_entries.content_hash` column is still fixed at 32 characters.
- `upsert_chunk_with_embedding` now requires an explicit `{success: true}` from `handle_ingest` before reporting `:created`/`:updated`. Failure hashes, missing success keys, and non-Hash returns are reported as `:skipped` with a warn log instead of false-positive success counts.

## [0.6.9] - 2026-04-27

### Fixed
- `Manifest.scan` no longer crashes on `Errno::EPERM`/`EACCES` encountered during corpus walk (common on macOS for TCC-protected paths like `~/Library/Accounts`). Unreadable subdirs are pruned with a debug log; scan continues. Replaced `Find.find` with a recursive walker that rescues per-dir; also tolerates `Errno::ELOOP` and `Errno::ENOENT` for files that disappear mid-scan.

## [0.6.7] - 2026-04-15

### Fixed
- `Runners::Query.retrieve_chunks` now extracts the `entries` array from `retrieve_relevant`'s Hash response instead of returning the Hash directly, preventing `TypeError: no implicit conversion of Symbol into Integer` on `knowledge query`
- `Runners::Maintenance.health` now returns `{ success: false, error: 'corpus_path is required' }` when called with `path: nil` and no settings fallback, instead of raising `TypeError: no implicit conversion of nil into String`; falls back to `Legion::Settings.dig(:knowledge, :corpus_path)` when available

## [0.6.6] - 2026-03-31

### Fixed
- `chunk_exists?` queries by `content_hash` column directly instead of LIKE on `text[]` tags column

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
