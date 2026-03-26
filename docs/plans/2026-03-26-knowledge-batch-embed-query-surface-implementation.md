# Implementation Plan: Batch Embedding + Knowledge Query Surface

**Date**: 2026-03-26
**Design doc**: `docs/plans/2026-03-26-knowledge-batch-embed-query-surface-design.md`

## Phase 1 — Batch embedding in lex-knowledge (ingest.rb)

### Task 1.1 — Add `batch_embed_chunks` private method

File: `lib/legion/extensions/knowledge/runners/ingest.rb`

Add after `generate_embedding`:

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
private_class_method :batch_embed_chunks
```

### Task 1.2 — Add `upsert_chunk_with_embedding` private method

Replace the embedding-generation step inside `upsert_chunk` with a pre-supplied value:

```ruby
def upsert_chunk_with_embedding(chunk, embedding, dry_run: false, force: false)
  return :created if dry_run
  return :created unless defined?(Legion::Extensions::Apollo)
  return :skipped if !force && chunk_exists?(chunk[:content_hash])

  ingest_to_apollo(chunk, embedding)
  force ? :updated : :created
rescue StandardError
  :skipped
end
private_class_method :upsert_chunk_with_embedding
```

The original `upsert_chunk` method and `generate_embedding` single-call helper were removed. All paths
(including `ingest_file`) now route through `batch_embed_chunks`; single-file is a batch of one.

### Task 1.3 — Update `process_file` to use batch path

Replace:
```ruby
chunks.each do |chunk|
  outcome = upsert_chunk(chunk, dry_run: dry_run, force: force)
  ...
end
```

With:
```ruby
paired = dry_run ? chunks.map { |c| { chunk: c, embedding: nil } }
                 : batch_embed_chunks(chunks, force: force)
paired.each do |p|
  outcome = upsert_chunk_with_embedding(p[:chunk], p[:embedding], dry_run: dry_run, force: force)
  ...
end
```

### Task 1.4 — Specs for batch embedding

File: `spec/legion/extensions/knowledge/runners/ingest_spec.rb`

Add describe block `batch embedding` covering:
- calls `embed_batch` once for all non-skipped chunks in a file
- maps vectors to correct chunks by index
- chunks with embed error get `nil` embedding but are still ingested
- skipped (existing) chunks are excluded from the batch call
- falls back gracefully when `Legion::LLM` is undefined

## Phase 2 — `legion knowledge` CLI subcommand (LegionIO)

### Task 2.1 — Create `lib/legion/cli/knowledge_command.rb`

```ruby
# frozen_string_literal: true

module Legion
  module CLI
    class Knowledge < Thor
      def self.exit_on_failure?
        true
      end

      class_option :json,     type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color, type: :boolean, default: false, desc: 'Disable color output'

      desc 'query QUESTION', 'Query the knowledge base with optional LLM synthesis'
      option :top_k,       type: :numeric, default: 5,    desc: 'Number of source chunks'
      option :synthesize,  type: :boolean, default: true,  desc: 'Synthesize an LLM answer'
      option :verbose,     type: :boolean, default: false, desc: 'Show full source metadata'
      def query(question)
        require_knowledge!
        result = knowledge_query.query(question: question, top_k: options[:top_k],
                                       synthesize: options[:synthesize])
        out = formatter
        if options[:json]
          out.json(result)
        elsif result[:success]
          out.header('Knowledge Query')
          if result[:answer]
            out.spacer
            puts result[:answer]
            out.spacer
          end
          print_sources(result[:sources] || [], out, verbose: options[:verbose])
        else
          out.warn("Query failed: #{result[:error]}")
        end
      end
      default_task :query

      desc 'retrieve QUESTION', 'Retrieve source chunks without LLM synthesis'
      option :top_k, type: :numeric, default: 5, desc: 'Number of source chunks'
      def retrieve(question)
        require_knowledge!
        result = knowledge_query.retrieve(question: question, top_k: options[:top_k])
        out = formatter
        if options[:json]
          out.json(result)
        elsif result[:success]
          out.header("Knowledge Retrieve (#{(result[:sources] || []).size} chunks)")
          print_sources(result[:sources] || [], out, verbose: true)
        else
          out.warn("Retrieve failed: #{result[:error]}")
        end
      end

      desc 'ingest PATH', 'Ingest a file or directory into the knowledge base'
      option :force,   type: :boolean, default: false, desc: 'Re-ingest even unchanged files'
      option :dry_run, type: :boolean, default: false, desc: 'Preview without writing'
      def ingest(path)
        require_ingest!
        result = if File.directory?(path)
                   knowledge_ingest.ingest_corpus(path: path, force: options[:force],
                                                  dry_run: options[:dry_run])
                 else
                   knowledge_ingest.ingest_file(file_path: path, force: options[:force])
                 end
        out = formatter
        if options[:json]
          out.json(result)
        elsif result[:success]
          out.success('Ingest complete')
          out.detail(result.reject { |k, _| k == :success })
        else
          out.warn("Ingest failed: #{result[:error]}")
        end
      end

      desc 'status', 'Show knowledge base status'
      def status
        require_ingest!
        result = knowledge_ingest.scan_corpus(path: ::Dir.pwd)
        out = formatter
        if options[:json]
          out.json(result)
        else
          out.header('Knowledge Status')
          out.detail({
                       'Path'       => result[:path].to_s,
                       'Files'      => result[:file_count].to_s,
                       'Total size' => "#{result[:total_bytes]} bytes"
                     })
        end
      end

      no_commands do
        def formatter
          @formatter ||= Output::Formatter.new(json: options[:json], color: !options[:no_color])
        end

        def require_knowledge!
          return if defined?(Legion::Extensions::Knowledge::Runners::Query)

          raise CLI::Error, 'lex-knowledge extension is not loaded. Install and enable it first.'
        end

        def require_ingest!
          return if defined?(Legion::Extensions::Knowledge::Runners::Ingest)

          raise CLI::Error, 'lex-knowledge extension is not loaded. Install and enable it first.'
        end

        def knowledge_query
          Legion::Extensions::Knowledge::Runners::Query
        end

        def knowledge_ingest
          Legion::Extensions::Knowledge::Runners::Ingest
        end

        def print_sources(sources, out, verbose:)
          return out.warn('No sources found') if sources.empty?

          out.header("Sources (#{sources.size})")
          sources.each_with_index do |s, i|
            score = format('%.2f', s[:score].to_f)
            heading = s[:heading].to_s.empty? ? '' : " § #{s[:heading]}"
            puts "  #{i + 1}. #{s[:source_file]}#{heading}   score: #{score}"
            puts "     #{truncate(s[:content].to_s, 100)}" if verbose
          end
        end

        def truncate(text, max)
          text.length > max ? "#{text[0..(max - 3)]}..." : text
        end
      end
    end
  end
end
```

### Task 2.2 — Wire in `lib/legion/cli.rb`

Add autoload:
```ruby
autoload :Knowledge, 'legion/cli/knowledge_command'
```

Add subcommand near other knowledge-related commands (e.g., after `apollo`):
```ruby
desc 'knowledge SUBCOMMAND', 'Search and manage the document knowledge base'
subcommand 'knowledge', Legion::CLI::Knowledge
```

### Task 2.3 — Specs for knowledge CLI

File: `spec/legion/cli/knowledge_command_spec.rb`

Cover:
- `query` calls `Runners::Query.query` with correct kwargs
- `query --no-synthesize` passes `synthesize: false`
- `query --json` outputs JSON
- `query` without lex-knowledge loaded raises CLI::Error
- `retrieve` calls `Runners::Query.retrieve`
- `ingest PATH` (file) calls `ingest_file`
- `ingest PATH` (directory) calls `ingest_corpus`
- `status` calls `scan_corpus`

## Phase 3 — `legion.query_knowledge` MCP tool (legion-mcp)

### Task 3.1 — Create `lib/legion/mcp/tools/query_knowledge.rb`

```ruby
# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class QueryKnowledge < ::MCP::Tool
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

        class << self
          def call(question:, top_k: 5, synthesize: true)
            return error_response('lex-knowledge is not available') unless knowledge_available?

            result = Legion::Extensions::Knowledge::Runners::Query.query(
              question:   question,
              top_k:      top_k,
              synthesize: synthesize
            )
            text_response(result)
          rescue StandardError => e
            Legion::Logging.warn("QueryKnowledge#call failed: #{e.message}") if defined?(Legion::Logging)
            error_response("Knowledge query failed: #{e.message}")
          end

          private

          def knowledge_available?
            defined?(Legion::Extensions::Knowledge::Runners::Query)
          end

          def text_response(data)
            ::MCP::Tool::Response.new([{ type: 'text', text: Legion::JSON.dump({ **data }) }])
          end

          def error_response(msg)
            ::MCP::Tool::Response.new([{ type: 'text', text: Legion::JSON.dump({ error: msg }) }], error: true)
          end
        end
      end
    end
  end
end
```

### Task 3.2 — Wire in `lib/legion/mcp/server.rb`

Add require (after existing mind_growth tools):
```ruby
require_relative 'tools/query_knowledge'
```

Add to `TOOL_CLASSES` array (after `MindGrowthHealth`):
```ruby
Tools::QueryKnowledge,
```

### Task 3.3 — Specs for MCP tool

File: `spec/legion/mcp/tools/query_knowledge_spec.rb`

Cover:
- `call(question: 'foo')` returns text response with result JSON when lex-knowledge available
- `call(question: 'foo', top_k: 3, synthesize: false)` passes kwargs through
- returns error response when lex-knowledge not defined
- returns error response when `Runners::Query.query` raises

## Dependencies and Ordering

1. Phase 1 (lex-knowledge) is independent — ship first.
2. Phase 2 (LegionIO CLI) is independent — can ship in parallel with Phase 1.
3. Phase 3 (legion-mcp) is independent — can ship in parallel with Phases 1 and 2.

## Version Bumps

| Repo | Current | New | Reason |
|------|---------|-----|--------|
| lex-knowledge | 0.3.0 | 0.4.0 | batch embedding changes ingest behavior |
| LegionIO | 1.5.18 | 1.5.19 | new `knowledge` subcommand |
| legion-mcp | 0.5.7 | 0.5.8 | new `legion.query_knowledge` tool (57 tools total) |

## Spec Counts Expected

- lex-knowledge: +~15 examples (batch embed + ingest delta coverage)
- LegionIO: +~20 examples (knowledge CLI command)
- legion-mcp: +~10 examples (query_knowledge tool)
