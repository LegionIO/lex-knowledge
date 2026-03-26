# lex-knowledge: Corpus Scanner + Document Parser Completion — Design

**Date**: 2026-03-25
**Status**: Draft
**Related**: `docs/work/ideas/lex-knowledge-design.md` phases 1.1 and 1.2

---

## Problem Statement

`lex-knowledge` has the skeleton of the document ingestion pipeline but two critical gaps prevent it from working correctly:

### Gap 1 — Manifest Persistence (Phase 1.1)

`Helpers::Manifest` has `scan` (walks the filesystem) and `diff` (computes added/changed/removed), but nothing ever persists the previous scan result. `CorpusWatcher` therefore has no previous manifest to diff against — every 300-second tick triggers a full re-ingest of every file in the corpus. This defeats the entire purpose of the manifest/diff design.

### Gap 2 — PDF/DOCX Parsing (Phase 1.2)

`Helpers::Parser#parse` returns `{ error: 'unsupported format', source_file: ... }` for `.pdf` and `.docx` files. `Legion::Data::Extract` (legion-data 1.6.6) provides a 10-handler registry that already handles these formats — it is simply not wired in.

### Gap 3 — Shallow Markdown Heading Tracking (Phase 1.2 completeness)

`parse_markdown` only recognises `#` and `##` heading levels. `###` and deeper fall through to the `else` branch and are appended as body text to the current section instead of creating sub-sections. Architecture documents commonly use 3–4 heading levels, so meaningful structural hierarchy is lost.

---

## Proposed Solution

### 1. `Helpers::ManifestStore` — Persistent Manifest

Add a new helper module `Helpers::ManifestStore` that reads and writes a JSON sidecar file for each corpus path.

**Storage location** (configurable, defaults to XDG-friendly path):

```ruby
~/.legionio/knowledge/<sha256_of_corpus_path>.manifest.json
```

The corpus path is SHA256-hashed so multiple corpus roots coexist without collision.

**File format** (array of manifest entries, matching `Manifest.scan` output):

```json
[
  { "path": "/docs/overview.md", "size": 4096, "mtime": "2026-03-20T10:00:00Z", "sha256": "abc..." },
  ...
]
```

**API:**

```ruby
# Load previous manifest (returns [] if none exists)
ManifestStore.load(corpus_path:)

# Persist current manifest
ManifestStore.save(corpus_path:, manifest:)

# Derive the sidecar file path (public for testing/CLI)
ManifestStore.store_path(corpus_path:)
```

**Integration into `Runners::Ingest#ingest_corpus`:**

```ruby
def ingest_corpus(path:)
  current  = Manifest.scan(path: path)
  previous = ManifestStore.load(corpus_path: path)
  delta    = Manifest.diff(current: current, previous: previous)

  # Only process files that changed
  (delta[:added] + delta[:changed]).each { |f| ingest_file(path: f) }

  # Soft-delete removed files from Apollo
  delta[:removed].each { |f| retire_file(path: f) }

  ManifestStore.save(corpus_path: path, manifest: current)

  { success: true, added: delta[:added].size, changed: delta[:changed].size, removed: delta[:removed].size }
end
```

**Fallback**: When no previous manifest exists, `diff` returns all files as `:added`, triggering a full ingest — identical behavior to today, but only on the first run.

**Store directory**: Created lazily with `FileUtils.mkdir_p` on first save.

---

### 2. `Helpers::Parser` — PDF/DOCX via `Legion::Data::Extract`

Extend `parse` to delegate to `Legion::Data::Extract` when the file type is unsupported natively, guarded by a constant check:

```ruby
def parse(file_path:)
  ext = ::File.extname(file_path).downcase
  case ext
  when '.md'  then parse_markdown(file_path: file_path)
  when '.txt' then parse_text(file_path: file_path)
  when '.pdf', '.docx'
    extract_via_data(file_path: file_path)
  else
    [{ error: 'unsupported format', source_file: file_path }]
  end
end

def extract_via_data(file_path:)
  unless defined?(::Legion::Data::Extract)
    return [{ error: 'unsupported format', source_file: file_path }]
  end

  result = ::Legion::Data::Extract.extract(file_path, type: :auto)
  return [{ error: 'extraction_failed', source_file: file_path, detail: result }] unless result[:text]

  heading = ::File.basename(file_path, '.*')
  [{ heading: heading, section_path: [], content: result[:text].strip, source_file: file_path }]
end
```

`Legion::Data::Extract.extract` returns `{ text:, metadata: }` on success, or a hash without `:text` on failure — the same contract as documented in legion-data 1.6.6.

**No section hierarchy for binary formats**: PDF/DOCX extraction returns a single section with the filename as heading. Structural parsing of these formats is out of scope; the content is chunked downstream by `Helpers::Chunker` anyway.

---

### 3. `parse_markdown` — Full Heading Depth (H1–H6)

Replace the two-branch `if/elsif` with a general heading-level detector. The section path is tracked as a stack keyed by heading depth:

```ruby
def parse_markdown(file_path:)
  content = ::File.read(file_path, encoding: 'utf-8')
  sections = []
  current_heading = ::File.basename(file_path, '.*')
  current_lines   = []
  heading_stack   = {}   # depth(int) => heading_title

  content.each_line do |line|
    level = heading_level(line)
    if level
      flush_section(sections, current_heading, build_section_path(heading_stack), current_lines, file_path)
      title = line.sub(/^#+\s*/, '').chomp
      heading_stack.delete_if { |d, _| d >= level }
      heading_stack[level] = title
      current_heading = title
      current_lines   = []
    else
      current_lines << line
    end
  end

  flush_section(sections, current_heading, build_section_path(heading_stack), current_lines, file_path)
  sections.empty? ? [{ heading: ::File.basename(file_path, '.*'), section_path: [], content: content.strip, source_file: file_path }] : sections
end

def heading_level(line)
  m = line.match(/^(#{1,6})\s/)
  m ? m[1].length : nil
end

def build_section_path(stack)
  stack.sort.map { |_, title| title }
end
```

This preserves the full ancestry chain (e.g., `["Architecture", "Boot Sequence", "Phase Handlers"]`) for `###`-level headings and deeper.

---

## Alternatives Considered

**SQLite table for manifest storage** — overkill. The manifest is a flat JSON array; a file is simpler, requires no schema migration, and works even when `legion-data` is not connected.

**Store manifest in Apollo** — creates a circular dependency: the manifest system bootstraps the ingest that feeds Apollo. Must stay independent.

**Full structural parsing for PDF/DOCX** — `Legion::Data::Extract` already does the heavy lifting. Adding heading-aware parsing for binary formats is a future enhancement, not a prerequisite.

---

## Constraints

- `ManifestStore` must work when `legion-data` is not connected (pure filesystem I/O only)
- `extract_via_data` must degrade gracefully when `Legion::Data::Extract` is not defined (same error shape as today)
- Manifest file writes must be atomic (write to `.tmp` then rename) to prevent corruption on crash
- No new gem dependencies

---

**Last Updated**: 2026-03-25
