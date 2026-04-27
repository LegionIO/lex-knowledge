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

    it 'treats extension filter as case-insensitive' do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, 'UPPER.MD'), '# upper')
        File.write(File.join(dir, 'mixed.TxT'), 'mixed')
        result = manifest.scan(path: dir)
        basenames = result.map { |e| File.basename(e[:path]) }
        expect(basenames).to contain_exactly('UPPER.MD', 'mixed.TxT')
      end
    end

    it 'skips dot-directories and does not recurse into them' do
      Dir.mktmpdir do |dir|
        hidden = File.join(dir, '.hidden_dir')
        FileUtils.mkdir_p(hidden)
        File.write(File.join(hidden, 'inside.md'), 'secret')
        File.write(File.join(dir, 'visible.md'), 'visible')
        result = manifest.scan(path: dir)
        paths = result.map { |e| e[:path] }
        expect(paths).not_to include(a_string_matching(%r{/\.hidden_dir/}))
        expect(paths.map { |p| File.basename(p) }).to eq(['visible.md'])
      end
    end

    it 'skips unreadable directories and continues scanning siblings' do
      Dir.mktmpdir do |tmp|
        readable = File.join(tmp, 'readable')
        locked   = File.join(tmp, 'locked')
        FileUtils.mkdir_p(readable)
        FileUtils.mkdir_p(locked)
        File.write(File.join(readable, 'a.md'), 'hello')
        File.write(File.join(locked,   'b.md'), 'nope')

        allow(Dir).to receive(:children).and_call_original
        allow(Dir).to receive(:children).with(locked).and_raise(Errno::EPERM)

        results = manifest.scan(path: tmp)
        paths   = results.map { |r| r[:path] }
        expect(paths).to include(end_with('/readable/a.md'))
        expect(paths).not_to include(end_with('/locked/b.md'))
      end
    end

    it 'skips unreadable directories raising Errno::EACCES' do
      Dir.mktmpdir do |tmp|
        readable = File.join(tmp, 'readable')
        locked   = File.join(tmp, 'locked')
        FileUtils.mkdir_p(readable)
        FileUtils.mkdir_p(locked)
        File.write(File.join(readable, 'a.md'), 'hello')

        allow(Dir).to receive(:children).and_call_original
        allow(Dir).to receive(:children).with(locked).and_raise(Errno::EACCES)

        results = manifest.scan(path: tmp)
        expect(results.map { |r| File.basename(r[:path]) }).to eq(['a.md'])
      end
    end

    it 'skips multiple unreadable subdirs at different depths without failing' do
      Dir.mktmpdir do |tmp|
        # tmp/
        #   top.md              <- readable
        #   locked1/            <- EPERM
        #   ok/
        #     mid.md            <- readable
        #     locked2/          <- EACCES
        File.write(File.join(tmp, 'top.md'), 'top')

        locked1 = File.join(tmp, 'locked1')
        FileUtils.mkdir_p(locked1)

        ok = File.join(tmp, 'ok')
        FileUtils.mkdir_p(ok)
        File.write(File.join(ok, 'mid.md'), 'mid')

        locked2 = File.join(ok, 'locked2')
        FileUtils.mkdir_p(locked2)

        allow(Dir).to receive(:children).and_call_original
        allow(Dir).to receive(:children).with(locked1).and_raise(Errno::EPERM)
        allow(Dir).to receive(:children).with(locked2).and_raise(Errno::EACCES)

        results = manifest.scan(path: tmp)
        basenames = results.map { |r| File.basename(r[:path]) }.sort
        expect(basenames).to eq(%w[mid.md top.md])
      end
    end

    it 'skips files that disappear between listing and read (ENOENT)' do
      Dir.mktmpdir do |tmp|
        good = File.join(tmp, 'good.md')
        gone = File.join(tmp, 'gone.md')
        File.write(good, 'keep me')
        File.write(gone, 'disappear')

        allow(File).to receive(:size).and_call_original
        allow(File).to receive(:size).with(gone).and_raise(Errno::ENOENT)

        results = manifest.scan(path: tmp)
        expect(results.map { |r| File.basename(r[:path]) }).to eq(['good.md'])
      end
    end

    it 'does not crash when the scan root itself is unreadable' do
      Dir.mktmpdir do |tmp|
        allow(File).to receive(:directory?).and_call_original
        allow(File).to receive(:directory?).with(tmp).and_raise(Errno::EPERM)

        expect { manifest.scan(path: tmp) }.not_to raise_error
        expect(manifest.scan(path: tmp)).to eq([])
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
