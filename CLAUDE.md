# lex-knowledge

**Level 3 Branch Documentation**
- **Parent**: `/Users/miverso2/rubymine/legion/extensions-agentic/CLAUDE.md`
- **Grandparent**: `/Users/miverso2/rubymine/legion/CLAUDE.md`

## Purpose

Document ingestion pipeline for LegionIO. Scans file corpora (markdown, text, PDF, DOCX), parses into structured sections, splits into overlapping token-bounded chunks, generates embeddings via `Legion::LLM`, and stores in Apollo (pgvector). Provides RAG query with optional LLM synthesis, corpus statistics, maintenance tools for chunk hygiene (orphan detection, reindex, quality reporting), and periodic health monitoring via background actors.

## Gem Info

- **Gem name**: `lex-knowledge`
- **Version**: `0.5.0`
- **Module**: `Legion::Extensions::Knowledge`
- **Ruby**: `>= 3.4`
- **License**: MIT

## File Structure

```
lib/legion/extensions/knowledge/
  version.rb
  client.rb                          # Standalone client — includes all four runner modules
  helpers/
    manifest.rb                      # Manifest.scan (SHA256 fingerprint per file), diff (added/changed/removed)
    manifest_store.rb                # Sidecar JSON persistence in ~/.legionio/knowledge/<hash>.manifest.json
    parser.rb                        # parse .md (heading-aware sections), .txt, .pdf/.docx (via Data::Extract)
    chunker.rb                       # Token-bounded splitting with paragraph overlap; CHARS_PER_TOKEN = 4
  runners/
    ingest.rb                        # scan_corpus, ingest_corpus (delta), ingest_file, batch embed + Apollo upsert
    query.rb                         # query (RAG + LLM synthesis), retrieve (chunks only), record_feedback
    corpus.rb                        # manifest_path, corpus_stats (estimated chunk count without embedding)
    maintenance.rb                   # detect_orphans, cleanup_orphans, reindex, health, quality_report
  actors/
    corpus_watcher.rb                # Every 300s: ingest_corpus — enabled only when corpus_path is set
    corpus_ingest.rb                 # Subscription: ingest_file on knowledge.ingest queue
    maintenance_runner.rb            # Every 21600s: health — enabled only when corpus_path is set
  transport/
    exchanges/
      knowledge.rb                   # topic exchange 'knowledge', durable
    queues/
      ingest.rb                      # durable queue 'knowledge.ingest', routing key 'knowledge.ingest'
    messages/
      ingest_message.rb              # publishes to 'knowledge' exchange with 'knowledge.ingest' routing key
spec/
  legion/extensions/knowledge/
    helpers/
      manifest_spec.rb
      manifest_store_spec.rb
      parser_spec.rb
      chunker_spec.rb
    runners/
      ingest_spec.rb
      query_spec.rb
      corpus_spec.rb
      maintenance_spec.rb
    actors/
      corpus_watcher_spec.rb
      corpus_ingest_spec.rb
      maintenance_runner_spec.rb
    integration_spec.rb
    transport_spec.rb
```

## File Map

| Path | Purpose |
|---|---|
| `lib/legion/extensions/knowledge.rb` | Entry point — requires all helpers, runners, client; conditionally loads transport (when `Legion::Transport` defined) and actors (when actor base classes defined) |
| `lib/legion/extensions/knowledge/version.rb` | `VERSION = '0.5.0'` |
| `lib/legion/extensions/knowledge/client.rb` | `Client` class — includes `Runners::Ingest`, `Runners::Query`, `Runners::Corpus`, `Runners::Maintenance` |
| `lib/legion/extensions/knowledge/helpers/manifest.rb` | `scan(path:, extensions:)` walks a directory tree and builds SHA256 fingerprint entries; `diff` computes added/changed/removed against a saved manifest |
| `lib/legion/extensions/knowledge/helpers/manifest_store.rb` | `load`/`save` sidecar JSON at `~/.legionio/knowledge/<16-char-sha>.manifest.json`; atomic write via `.tmp` + rename |
| `lib/legion/extensions/knowledge/helpers/parser.rb` | `parse(file_path:)` dispatches by extension; markdown produces heading-scoped sections; text produces single section; PDF/DOCX delegates to `Legion::Data::Extract` |
| `lib/legion/extensions/knowledge/helpers/chunker.rb` | `chunk(sections:, max_tokens:, overlap_tokens:)` splits by paragraph, carries overlap tail between chunks, hard-slices oversized paragraphs; settings read from `Legion::Settings.dig(:knowledge, :chunker, *)` |
| `lib/legion/extensions/knowledge/runners/ingest.rb` | `scan_corpus`, `ingest_corpus` (delta-driven), `ingest_file`; uses `LLM.embed_batch` for vectorization; upserts via `Apollo::Runners::Knowledge.handle_ingest`; retires removed files via `Legion::Apollo.ingest` |
| `lib/legion/extensions/knowledge/runners/query.rb` | `query(question:, top_k:, synthesize:)` retrieves from Apollo then optionally synthesizes with `LLM.chat`; `retrieve` returns raw chunks only; `record_feedback` emits `knowledge.query_feedback` event |
| `lib/legion/extensions/knowledge/runners/corpus.rb` | `manifest_path` and `corpus_stats` (file count + estimated chunk count, no embedding) |
| `lib/legion/extensions/knowledge/runners/maintenance.rb` | `detect_orphans`, `cleanup_orphans`, `reindex`, `health` (local + apollo + sync stats), `quality_report` (hot/cold/low-confidence chunks) |
| `lib/legion/extensions/knowledge/actors/corpus_watcher.rb` | `Every` actor; fires `ingest_corpus` at `watcher_interval` (300s default); disabled when `corpus_path` is nil/empty |
| `lib/legion/extensions/knowledge/actors/corpus_ingest.rb` | `Subscription` actor on `knowledge.ingest`; fires `ingest_file` per message |
| `lib/legion/extensions/knowledge/actors/maintenance_runner.rb` | `Every` actor; fires `health` at `maintenance_interval` (21600s default); disabled when `corpus_path` is nil/empty |
| `lib/legion/extensions/knowledge/transport/exchanges/knowledge.rb` | Durable topic exchange `knowledge` |
| `lib/legion/extensions/knowledge/transport/queues/ingest.rb` | Durable queue `knowledge.ingest` bound to routing key `knowledge.ingest` |
| `lib/legion/extensions/knowledge/transport/messages/ingest_message.rb` | `IngestMessage` — publishes single-file ingest requests to `knowledge.ingest` |

## Dependencies

| Dependency | Used For |
|---|---|
| `legion-data` | `Legion::Data::Extract` for PDF/DOCX text extraction; `Legion::Data::Model::ApolloEntry` / `ApolloAccessLog` queries in maintenance |
| `legion-llm` | `Legion::LLM.embed_batch` for chunk vectorization; `Legion::LLM.chat` for RAG synthesis |
| `lex-apollo` / `legion-apollo` | `Apollo::Runners::Knowledge.handle_ingest` / `retrieve_relevant`; `Legion::Apollo.ingest` for retire events |
| `legion-settings` | `Legion::Settings.dig(:knowledge, ...)` for all tunable defaults |
| `legion-transport` | AMQP exchange/queue/message classes (loaded conditionally) |

## Settings Reference

```yaml
knowledge:
  corpus_path: ~                  # absolute path to scan; actors disabled when nil
  chunker:
    max_tokens: 512               # max tokens per chunk (CHARS_PER_TOKEN = 4, so 2048 chars)
    overlap_tokens: 128           # overlap tail carried into next chunk (512 chars)
  query:
    top_k: 5                      # default number of chunks to retrieve
  maintenance:
    stale_threshold: 0.3          # confidence below which a chunk is considered stale/low-quality
    cold_chunk_days: 7            # days since creation with zero access to classify as cold
    quality_report_limit: 10      # max entries per category in quality_report
  actors:
    watcher_interval: 300         # seconds between corpus scans (CorpusWatcher)
    maintenance_interval: 21600   # seconds between health runs (MaintenanceRunner) — 6 hours
```

## Key Patterns

**ManifestStore sidecar delta-driven ingestion**: `ingest_corpus` compares the current on-disk SHA256 manifest against the saved sidecar. Only added/changed files are re-processed; removed files are retired. This prevents re-embedding unchanged documents on every watcher cycle.

**Graceful degradation**: Every external call (`Legion::Data::Extract`, `Legion::LLM`, `Legion::Extensions::Apollo`, `Legion::Data::Model::*`) is guarded by `defined?` and wrapped in `rescue StandardError`. Ingestion continues without embeddings if LLM is unavailable; maintenance stats fall back to zero-valued defaults if Data is unavailable.

**`module_function` + `private_class_method` runner pattern**: All runners use `module_function` so methods are callable as `Runners::Ingest.scan_corpus(...)`. Internal helpers are declared with `private_class_method` to keep the public API clean.

**All public runner methods return `{ success: true/false, ... }` hashes**: Errors are caught at the outermost method boundary and returned as `{ success: false, error: e.message }`.

**Actor enable gating**: `CorpusWatcher` and `MaintenanceRunner` override `enabled?` to return `false` when `corpus_path` is nil or empty, preventing empty-path errors from running on nodes that do not host a corpus.

**Transport conditional loading**: Exchange, queue, and message classes are only required when `Legion::Transport` is defined. Actor classes are only required when `Legion::Extensions::Actors::Every` or `::Subscription` are defined. This allows the gem to be used in lite mode or in standalone scripts.

## Development

```bash
bundle install
bundle exec rspec       # 143 examples, 0 failures
bundle exec rubocop     # 0 offenses
```

## Pre-Push Pipeline

See parent `legion/CLAUDE.md` for the full required pipeline (rspec → rubocop -A → rubocop → version bump → CHANGELOG → README → push).

---

**Maintained By**: Matthew Iverson (@Esity)
