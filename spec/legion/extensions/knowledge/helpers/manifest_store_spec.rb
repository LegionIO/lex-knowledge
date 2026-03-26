# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions::Knowledge::Helpers::ManifestStore do
  subject(:store) { described_class }

  let(:tmp_dir) { Dir.mktmpdir }
  let(:corpus_path) { File.join(tmp_dir, 'corpus') }

  after { FileUtils.remove_entry(tmp_dir) }

  # Override STORE_DIR to a temp location so tests don't write to ~/.legionio
  before do
    stub_const('Legion::Extensions::Knowledge::Helpers::ManifestStore::STORE_DIR', tmp_dir)
  end

  describe '.load' do
    it 'returns an empty array when no manifest file exists' do
      expect(store.load(corpus_path: corpus_path)).to eq([])
    end

    it 'returns parsed entries after save' do
      manifest = [{ path: '/docs/a.md', size: 100, mtime: Time.now.to_s, sha256: 'abc123' }]
      store.save(corpus_path: corpus_path, manifest: manifest)
      result = store.load(corpus_path: corpus_path)
      expect(result.first[:path]).to eq('/docs/a.md')
      expect(result.first[:sha256]).to eq('abc123')
    end

    it 'returns symbol keys' do
      manifest = [{ path: '/a.md', size: 10, mtime: Time.now.to_s, sha256: 'x' }]
      store.save(corpus_path: corpus_path, manifest: manifest)
      result = store.load(corpus_path: corpus_path)
      expect(result.first.keys).to all(be_a(Symbol))
    end

    it 'returns empty array on corrupt file' do
      path = store.store_path(corpus_path: corpus_path)
      File.write(path, 'not valid json{{{')
      expect(store.load(corpus_path: corpus_path)).to eq([])
    end
  end

  describe '.save' do
    it 'persists entries to disk' do
      manifest = [{ path: '/x.md', size: 50, mtime: Time.now.to_s, sha256: 'def456' }]
      result = store.save(corpus_path: corpus_path, manifest: manifest)
      expect(result).to be true
      expect(File.exist?(store.store_path(corpus_path: corpus_path))).to be true
    end

    it 'writes atomically (no .tmp file left behind)' do
      store.save(corpus_path: corpus_path, manifest: [])
      tmp_path = "#{store.store_path(corpus_path: corpus_path)}.tmp"
      expect(File.exist?(tmp_path)).to be false
    end

    it 'serializes Time mtime as a string' do
      t = Time.now
      manifest = [{ path: '/b.md', size: 20, mtime: t, sha256: 'zzz' }]
      store.save(corpus_path: corpus_path, manifest: manifest)
      raw = JSON.parse(File.read(store.store_path(corpus_path: corpus_path)))
      expect(raw.first['mtime']).to be_a(String)
    end

    it 'survives roundtrip with Time mtime (mtime comes back as string)' do
      t = Time.now
      manifest = [{ path: '/c.md', size: 5, mtime: t, sha256: 'roundtrip' }]
      store.save(corpus_path: corpus_path, manifest: manifest)
      loaded = store.load(corpus_path: corpus_path)
      expect(loaded.first[:mtime]).to be_a(String)
      expect(loaded.first[:sha256]).to eq('roundtrip')
    end
  end

  describe '.store_path' do
    it 'is deterministic — same input always returns the same path' do
      path1 = store.store_path(corpus_path: '/docs/project')
      path2 = store.store_path(corpus_path: '/docs/project')
      expect(path1).to eq(path2)
    end

    it 'produces different paths for different corpus roots' do
      path1 = store.store_path(corpus_path: '/docs/project')
      path2 = store.store_path(corpus_path: '/other/project')
      expect(path1).not_to eq(path2)
    end

    it 'uses only first 16 chars of SHA256 in the filename' do
      path = store.store_path(corpus_path: corpus_path)
      filename = File.basename(path, '.manifest.json')
      expect(filename.length).to eq(16)
    end

    it 'ends with .manifest.json' do
      expect(store.store_path(corpus_path: corpus_path)).to end_with('.manifest.json')
    end
  end
end
