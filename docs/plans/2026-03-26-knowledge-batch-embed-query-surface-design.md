# Design: Batch Embedding + Knowledge Query Surface

**Date**: 2026-03-26
**Repos**: lex-knowledge (primary), LegionIO (sub), legion-mcp (sub)
**Status**: Draft

## Problem

### 1. Embedding bottleneck in ingest pipeline

`Runners::Ingest#process_file` calls `generate_embedding(chunk[:content])` for every individual
chunk that needs ingestion. `generate_embedding` calls `Legion::LLM.embed(content)` — one HTTP
round-trip per chunk. For a 1 000-chunk corpus this means 1 000 sequential API calls. The Embeddings
module already exposes `Legion::LLM.embed_batch(texts)` which accepts an array and returns all
vectors in a single call, but it is never used by the ingest pipeline.

### 2. No CLI access to knowledge query

`Runners::Query` ships a fully-implemented `query(question:, top_k:, synthesize:)` method but there
is no `legion knowledge` CLI subcommand. Users who want to search the knowledge base must call the
REST API directly or drop into a Ruby repl. This limits discoverability.

### 3. No MCP surface for knowledge queries

MCP clients (Claude, Cursor, etc.) cannot search the knowledge base without custom integration. A
`legion.query_knowledge` tool would expose query + optional synthesis directly to AI models.

## Proposed Solution

### 1. Batch embedding in lex-knowledge

Restructure `process_file` to collect all chunk contents that actually need ingestion, call
`Legion::LLM.embed_batch` once per file, then distribute the returned vectors before upserting.

**New private method** `batch_embed_chunks(chunks, force:)`:

```ruby
def batch_embed_chunks(chunks, force:)
  return chunks.map { |c| { chunk: c, embedding: nil } } unless defined?(Legion::LLM) &&
                                                                   Legion::LLM.respond_to?(:embed_batch)

  needs_embed = force ? chunks : chunks.reject { |c| chunk_exists?(c[:content_hash]) }
  return chunks.map { |c| { chunk: c, embedding: nil } } if needs_embed.empty?

  results = Legion::LLM.embed_batch(needs_embed.map { |c| c[:content] })
  embed_map = results.each_with_object({}) do |r, h|
    h[needs_embed[r[:index]][:content_hash]] = r[:vector] unless r[:error]
  end

  chunks.map { |c| { chunk: c, embedding: embed_map[c[:content_hash]] } }
rescue StandardError
  chunks.map { |c| { chunk: c, embedding: nil } }
end
```

**Updated `process_file`**:

```ruby
def process_file(file_path, dry_run: false, force: false)
  sections = Helpers::Parser.parse(file_path: file_path)
  return { created: 0, skipped: 0, updated: 0 } if sections.first&.key?(:error)

  chunks = Helpers::Chunker.chunk(sections: sections)
  paired = dry_run ? chunks.map { |c| { chunk: c, embedding: nil } }
                   : batch_embed_chunks(chunks, force: force)

  created = skipped = updated = 0
  paired.each do |p|
    outcome = upsert_chunk_with_embedding(p[:chunk], p[:embedding], dry_run: dry_run, force: force)
    case outcome
    when :created then created += 1
    when :skipped then skipped += 1
    when :updated then updated += 1
    end
  end

  { created: created, skipped: skipped, updated: updated }
end
```

`upsert_chunk_with_embedding` is the existing `upsert_chunk` accepting a pre-computed embedding
instead of calling `generate_embedding` internally.

**Fallback**: if `embed_batch` raises or returns partial errors, affected chunks get `nil` embedding
and are still ingested (just without a vector for semantic search). The old `generate_embedding`
single-call helper is retained as a private fallback for `ingest_file` (single-file ad-hoc ingestion
where batching adds no value).

### 2. `legion knowledge` CLI subcommand in LegionIO

New `CLI::Knowledge < Thor` class at `lib/legion/cli/knowledge_command.rb`.

```
legion knowledge query QUESTION [--top-k N] [--no-synthesize] [--verbose] [--json]
legion knowledge retrieve QUESTION [--top-k N] [--json]
legion knowledge ingest PATH [--force] [--dry-run] [--json]
legion knowledge status [--json]
```

`query` calls `Runners::Query.query(question:, top_k:, synthesize:)` and formats the result:

```
Answer: <synthesized text or raw source list>

Sources (3):
  1. README.md § Architecture    score: 0.91
  2. docs/guide.md § Installation  score: 0.87
  3. CHANGELOG.md § v1.2.0        score: 0.83
```

`retrieve` calls `Runners::Query.retrieve(question:, top_k:)` (no synthesis) and shows a sources
table with heading + score columns.

Both commands guard with:

```ruby
def require_knowledge!
  return if defined?(Legion::Extensions::Knowledge::Runners::Query)
  raise CLI::Error, 'lex-knowledge extension is not loaded. Install and enable it first.'
end
```

`ingest` and `status` are thin wrappers over `Runners::Ingest.ingest_corpus` /
`Runners::Corpus.list_corpus`.  These surface existing functionality from the CLI for the first time.

Wire in `lib/legion/cli.rb`:

```ruby
autoload :Knowledge, 'legion/cli/knowledge_command'
# ...
desc 'knowledge SUBCOMMAND', 'Search and manage the document knowledge base'
subcommand 'knowledge', Legion::CLI::Knowledge
```

### 3. `legion.query_knowledge` MCP tool in legion-mcp

New `Tools::QueryKnowledge < ::MCP::Tool` at
`lib/legion/mcp/tools/query_knowledge.rb`.

```ruby
tool_name 'legion.query_knowledge'
description 'Search the document knowledge base. Returns a synthesized answer and ranked source chunks.'

input_schema(
  properties: {
    question:  { type: 'string',  description: 'The question or search query' },
    top_k:     { type: 'integer', description: 'Number of source chunks to retrieve (default 5)' },
    synthesize:{ type: 'boolean', description: 'Whether to synthesize an LLM answer (default true)' }
  },
  required: %w[question]
)
```

```ruby
def call(question:, top_k: 5, synthesize: true)
  return error_response('lex-knowledge is not available') unless knowledge_available?

  result = Legion::Extensions::Knowledge::Runners::Query.query(
    question:  question,
    top_k:     top_k,
    synthesize: synthesize
  )
  text_response(result)
rescue StandardError => e
  error_response("Knowledge query failed: #{e.message}")
end
```

Wire in `server.rb`:

```ruby
require_relative 'tools/query_knowledge'
# ...
TOOL_CLASSES = [
  # ...
  Tools::QueryKnowledge,
  # ...
].freeze
```

## Alternatives Considered

- **Streaming embed**: `embed_batch` returns all results synchronously via the RubyLLM SDK — there
  is no streaming API, so single-call batch is the best we can do.
- **Per-process-file batching vs full-corpus batching**: batching at the file level is safe and
  bounded. Full-corpus batching could OOM on very large corpora. File-level is the right scope.
- **Skip `ingest` and `status` from the Knowledge CLI**: deferred to avoid scope creep — those
  runners already exist and the CLI wrappers are trivial; including them prevents a second issue
  for adding them later.

## Constraints

- `Legion::LLM.embed_batch` returns `Array<{vector:, model:, provider:, dimensions:, index:}>`.
  The `index:` field is the position in the input array — use it for correct mapping.
- `MCP::Tool::Response.new` takes `[{type: 'text', text: String}]` — dump result as JSON string.
- Thor 1.5+: `run` is a reserved method — avoid it as a subcommand name.
- Guard all extension calls with `defined?()` — the tool and CLI should degrade gracefully.

## File Map

| File | Repo | Change |
|------|------|--------|
| `lib/legion/extensions/knowledge/runners/ingest.rb` | lex-knowledge | replace per-chunk embed with batch; add `batch_embed_chunks`, `upsert_chunk_with_embedding` |
| `spec/legion/extensions/knowledge/runners/ingest_spec.rb` | lex-knowledge | batch embed specs |
| `lib/legion/cli/knowledge_command.rb` | LegionIO | new file |
| `lib/legion/cli.rb` | LegionIO | autoload + subcommand |
| `spec/legion/cli/knowledge_command_spec.rb` | LegionIO | new file |
| `lib/legion/mcp/tools/query_knowledge.rb` | legion-mcp | new file |
| `lib/legion/mcp/server.rb` | legion-mcp | require + TOOL_CLASSES entry |
| `spec/legion/mcp/tools/query_knowledge_spec.rb` | legion-mcp | new file |
