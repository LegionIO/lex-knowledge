# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions::Knowledge::Helpers::Manifest do
  subject(:manifest) { described_class }

  describe '.scan' do
    it 'returns an array of file entries with required keys' do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, 'doc.md'), '# Hello')
        result = manifest.scan(path: dir)
        expect(result).to be_an(Array)
        expect(result.first).to include(:path, :size, :mtime, :sha256)
      end
    end

    it 'only returns files matching the given extensions' do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, 'a.md'),  '# A')
        File.write(File.join(dir, 'b.txt'), 'B')
        File.write(File.join(dir, 'c.rb'),  'C')
        result = manifest.scan(path: dir, extensions: %w[.md])
        expect(result.map { |e| File.extname(e[:path]) }).to all(eq('.md'))
        expect(result.size).to eq(1)
      end
    end

    it 'skips hidden files (beginning with dot)' do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, '.hidden.md'), 'hidden')
        File.write(File.join(dir, 'visible.md'), 'visible')
        result = manifest.scan(path: dir)
        expect(result.map { |e| File.basename(e[:path]) }).not_to include('.hidden.md')
        expect(result.size).to eq(1)
      end
    end

    it 'computes a non-empty sha256 digest for each file' do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, 'doc.txt'), 'content')
        result = manifest.scan(path: dir, extensions: %w[.txt])
        expect(result.first[:sha256]).to match(/\A[0-9a-f]{64}\z/)
      end
    end

    it 'returns an empty array for an empty directory' do
      Dir.mktmpdir do |dir|
        result = manifest.scan(path: dir)
        expect(result).to eq([])
      end
    end

    it 'recurses into subdirectories' do
      Dir.mktmpdir do |dir|
        subdir = File.join(dir, 'sub')
        FileUtils.mkdir_p(subdir)
        File.write(File.join(subdir, 'nested.md'), '# Nested')
        result = manifest.scan(path: dir)
        expect(result.size).to eq(1)
        expect(result.first[:path]).to include('nested.md')
      end
    end
  end

  describe '.diff' do
    it 'detects added files' do
      current  = [{ path: '/a.md', sha256: 'abc' }]
      previous = []
      result   = manifest.diff(current: current, previous: previous)
      expect(result[:added]).to include('/a.md')
      expect(result[:removed]).to be_empty
      expect(result[:changed]).to be_empty
    end

    it 'detects removed files' do
      current  = []
      previous = [{ path: '/old.md', sha256: 'xyz' }]
      result   = manifest.diff(current: current, previous: previous)
      expect(result[:removed]).to include('/old.md')
      expect(result[:added]).to be_empty
    end

    it 'detects changed files when sha256 differs' do
      current  = [{ path: '/doc.md', sha256: 'new_hash' }]
      previous = [{ path: '/doc.md', sha256: 'old_hash' }]
      result   = manifest.diff(current: current, previous: previous)
      expect(result[:changed]).to include('/doc.md')
      expect(result[:added]).to be_empty
      expect(result[:removed]).to be_empty
    end

    it 'reports no changes when sha256 is identical' do
      entry    = { path: '/doc.md', sha256: 'same' }
      result   = manifest.diff(current: [entry], previous: [entry.dup])
      expect(result[:added]).to be_empty
      expect(result[:removed]).to be_empty
      expect(result[:changed]).to be_empty
    end

    it 'handles empty current and previous' do
      result = manifest.diff(current: [], previous: [])
      expect(result).to eq({ added: [], changed: [], removed: [] })
    end
  end
end
