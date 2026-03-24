# Changelog

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
