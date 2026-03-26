# lex-knowledge: Corpus Scanner + Document Parser Completion — Implementation Plan

**Date**: 2026-03-25
**Design Doc**: `docs/plans/2026-03-25-corpus-scanner-parser-design.md`
**Target Repo**: `LegionIO/lex-knowledge`
**Current Version**: 0.2.0

---

## Phase 1: `Helpers::ManifestStore`

### Task 1.1 — Create `helpers/manifest_store.rb`

**File**: `lib/legion/extensions/knowledge/helpers/manifest_store.rb`

```ruby
# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'tempfile'

module Legion
  module Extensions
    module Knowledge
      module Helpers
        module ManifestStore
          module_function

          STORE_DIR = ::File.expand_path('~/.legionio/knowledge').freeze

          def load(corpus_path:)
            path = store_path(corpus_path: corpus_path)
            return [] unless ::File.exist?(path)

            raw = ::File.read(path, encoding: 'utf-8')
            ::JSON.parse(raw, symbolize_names: true)
          rescue StandardError
            []
          end

          def save(corpus_path:, manifest:)
            ::FileUtils.mkdir_p(STORE_DIR)
            path = store_path(corpus_path: corpus_path)
            tmp  = "#{path}.tmp"
            ::File.write(tmp, ::JSON.generate(manifest.map { |e| serialize_entry(e) }))
            ::File.rename(tmp, path)
            true
          rescue StandardError
            false
          end

          def store_path(corpus_path:)
            hash = ::Digest::SHA256.hexdigest(corpus_path.to_s)[0, 16]
            ::File.join(STORE_DIR, "#{hash}.manifest.json")
          end

          def serialize_entry(entry)
            entry.merge(mtime: entry[:mtime].to_s)
          end
          private_class_method :serialize_entry
        end
      end
    end
  end
end
```

### Task 1.2 — Wire `ManifestStore` into `Runners::Ingest#ingest_corpus`

**File**: `lib/legion/extensions/knowledge/runners/ingest.rb`

- `require` `helpers/manifest_store` at the top of the file
- Replace the current `ingest_corpus` body with the delta-driven version from the design doc
- Add private `retire_file(path:)` method: calls `Legion::Apollo.ingest` with a `retired: true` flag (soft delete signal) if Apollo is available, otherwise no-op

### Task 1.3 — Expose `store_path` via `Runners::Corpus`

**File**: `lib/legion/extensions/knowledge/runners/corpus.rb`

- Add `manifest_path` function:
  ```ruby
  def manifest_path(path:)
    ManifestStore.store_path(corpus_path: path)
  end
  ```
- Returns the filesystem path for introspection / CLI use

---

## Phase 2: `Helpers::Parser` — PDF/DOCX + Deep Headings

### Task 2.1 — Add `extract_via_data` to `Helpers::Parser`

**File**: `lib/legion/extensions/knowledge/helpers/parser.rb`

- Add `.docx` and `.pdf` to the `case` statement, delegating to `extract_via_data`
- Add `extract_via_data(file_path:)` private method (guarded by `defined?(::Legion::Data::Extract)`)
- Return shape matches existing section format: `{ heading:, section_path: [], content:, source_file: }`

### Task 2.2 — Deepen `parse_markdown` to H1–H6

**File**: `lib/legion/extensions/knowledge/helpers/parser.rb`

- Replace `if line.start_with?('# ') / elsif line.start_with?('## ')` with general `heading_level(line)` detector
- Add `heading_stack` hash (depth → title) to track parent hierarchy
- Add `build_section_path(stack)` to emit sorted ancestry array
- Add private `heading_level(line)` → Integer or nil

---

## Phase 3: Specs

### Task 3.1 — Spec for `ManifestStore`

**File**: `spec/helpers/manifest_store_spec.rb`

Cover:
- `load` returns `[]` when no file exists
- `load` returns parsed entries after `save`
- `save` persists entries and is atomic (writes tmp then renames)
- `save` returns `false` on unwritable path (permission error)
- `store_path` is deterministic — same input always returns same path
- `store_path` uses only the first 16 chars of SHA256 (avoids OS filename limits)
- Two different corpus paths produce different store paths
- Roundtrip: entries with `mtime` as Time object survive save/load as string

### Task 3.2 — Spec for `ingest_corpus` delta behavior

**File**: `spec/runners/ingest_spec.rb` (extend existing)

Cover:
- First run (no manifest): all files processed as `added`
- Second run (no changes): zero files processed, manifest re-saved
- Second run (one file changed): only that file re-ingested
- Removed file: `retire_file` called, not `ingest_file`
- `ManifestStore.save` called after each run with updated manifest

### Task 3.3 — Spec for Parser PDF/DOCX delegation

**File**: `spec/helpers/parser_spec.rb` (extend existing)

Cover:
- `.pdf` with `Data::Extract` available: delegates, returns single section
- `.pdf` with `Data::Extract` absent: returns `{ error: 'unsupported format' }`
- `.pdf` with `Data::Extract` returning no `:text`: returns `{ error: 'extraction_failed' }`
- `.docx` same three cases
- `extract_via_data` uses the filename (without extension) as heading
- `extract_via_data` sets `section_path: []`

### Task 3.4 — Spec for `parse_markdown` heading depth

**File**: `spec/helpers/parser_spec.rb` (extend existing)

Cover:
- `###` heading creates a new section with 3-element `section_path`
- `####` creates 4-element `section_path`
- After `###` under `##`, going back to `##` resets the sub-path (no stale `###` ancestor)
- Mixed depth document produces correct ancestry chains
- Document with only `###` (no `#` or `##`) still works

---

## Files Changed

| File | Action |
|------|--------|
| `lib/legion/extensions/knowledge/helpers/manifest_store.rb` | Create |
| `lib/legion/extensions/knowledge/helpers/parser.rb` | Modify (extract_via_data + deep headings) |
| `lib/legion/extensions/knowledge/runners/ingest.rb` | Modify (delta-driven ingest_corpus + retire_file) |
| `lib/legion/extensions/knowledge/runners/corpus.rb` | Modify (add manifest_path function) |
| `lib/legion/extensions/knowledge.rb` | Modify (autoload ManifestStore) |
| `spec/helpers/manifest_store_spec.rb` | Create |
| `spec/helpers/parser_spec.rb` | Modify (add PDF/DOCX + deep heading examples) |
| `spec/runners/ingest_spec.rb` | Modify (add delta-driven examples) |

---

## Acceptance Criteria

1. `CorpusWatcher` tick on an unchanged corpus produces zero Apollo writes, manifest unchanged
2. Adding a single file to corpus: next tick processes only that file
3. Deleting a file from corpus: next tick calls `retire_file` (not `ingest_file`) for that path
4. Parsing a `.pdf` with `Data::Extract` available returns `[{ heading:, section_path: [], content:, source_file: }]`
5. Parsing a `.pdf` without `Data::Extract` returns `[{ error: 'unsupported format', ... }]` (no crash)
6. A markdown document with `###` headings produces sections with 3-element `section_path` arrays
7. All specs green, zero rubocop offenses
8. Version bumped to 0.3.0

---

**Last Updated**: 2026-03-25
