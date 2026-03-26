# frozen_string_literal: true

RSpec.describe Legion::Extensions::Knowledge::Runners::Monitor do
  let(:tmp_dir) { Dir.mktmpdir }

  after { FileUtils.remove_entry(tmp_dir) }

  # ---------------------------------------------------------------------------
  # .resolve_monitors
  # ---------------------------------------------------------------------------

  describe '.resolve_monitors' do
    context 'when no settings are defined' do
      before do
        allow(described_class).to receive(:read_monitors_setting).and_return(nil)
        allow(described_class).to receive(:read_legacy_corpus_path).and_return(nil)
      end

      it 'returns an empty array' do
        expect(described_class.resolve_monitors).to eq([])
      end
    end

    context 'when monitors array is set' do
      let(:monitors) { [{ path: tmp_dir, extensions: %w[.md], label: 'docs' }] }

      before do
        allow(described_class).to receive(:read_monitors_setting).and_return(monitors)
        allow(described_class).to receive(:read_legacy_corpus_path).and_return(nil)
      end

      it 'returns the monitors array' do
        result = described_class.resolve_monitors
        expect(result.size).to eq(1)
        expect(result.first[:path]).to eq(tmp_dir)
      end
    end

    context 'when legacy corpus_path is set and not already in monitors' do
      before do
        allow(described_class).to receive(:read_monitors_setting).and_return([])
        allow(described_class).to receive(:read_legacy_corpus_path).and_return(tmp_dir)
      end

      it 'appends a legacy entry' do
        result = described_class.resolve_monitors
        expect(result.size).to eq(1)
        expect(result.first[:path]).to eq(tmp_dir)
        expect(result.first[:label]).to eq('legacy')
      end

      it 'sets default extensions on the legacy entry' do
        result = described_class.resolve_monitors
        expect(result.first[:extensions]).to include('.md', '.txt', '.docx', '.pdf')
      end
    end

    context 'when legacy corpus_path is already in monitors' do
      let(:monitors) { [{ path: tmp_dir, extensions: %w[.md], label: 'docs' }] }

      before do
        allow(described_class).to receive(:read_monitors_setting).and_return(monitors)
        allow(described_class).to receive(:read_legacy_corpus_path).and_return(tmp_dir)
      end

      it 'does not add a duplicate entry' do
        result = described_class.resolve_monitors
        expect(result.size).to eq(1)
      end
    end

    context 'when an error is raised internally' do
      before do
        allow(described_class).to receive(:read_monitors_setting).and_raise(RuntimeError, 'boom')
      end

      it 'returns an empty array' do
        expect(described_class.resolve_monitors).to eq([])
      end
    end
  end

  # ---------------------------------------------------------------------------
  # .add_monitor
  # ---------------------------------------------------------------------------

  describe '.add_monitor' do
    before do
      allow(described_class).to receive(:read_monitors_setting).and_return([])
      allow(described_class).to receive(:persist_monitors).and_return(true)
    end

    it 'returns success: true for a valid directory' do
      result = described_class.add_monitor(path: tmp_dir)
      expect(result[:success]).to be true
    end

    it 'returns a monitor entry on success' do
      result = described_class.add_monitor(path: tmp_dir)
      expect(result[:monitor]).to be_a(Hash)
      expect(result[:monitor][:path]).to eq(tmp_dir)
    end

    it 'uses the basename as the default label' do
      result = described_class.add_monitor(path: tmp_dir)
      expect(result[:monitor][:label]).to eq(File.basename(tmp_dir))
    end

    it 'applies the custom label when provided' do
      result = described_class.add_monitor(path: tmp_dir, label: 'my-docs')
      expect(result[:monitor][:label]).to eq('my-docs')
    end

    it 'uses DEFAULT_EXTENSIONS when no extensions are given' do
      result = described_class.add_monitor(path: tmp_dir)
      expect(result[:monitor][:extensions]).to eq(described_class::DEFAULT_EXTENSIONS.dup)
    end

    it 'accepts custom extensions' do
      result = described_class.add_monitor(path: tmp_dir, extensions: %w[.rst])
      expect(result[:monitor][:extensions]).to eq(%w[.rst])
    end

    it 'includes an added_at ISO 8601 timestamp' do
      result = described_class.add_monitor(path: tmp_dir)
      expect(result[:monitor][:added_at]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
    end

    it 'persists the new entry via persist_monitors' do
      expect(described_class).to receive(:persist_monitors)
        .with(array_including(hash_including(path: tmp_dir)))
        .and_return(true)
      described_class.add_monitor(path: tmp_dir)
    end

    context 'when the path does not exist' do
      it 'returns success: false' do
        result = described_class.add_monitor(path: '/nonexistent/path/abc123')
        expect(result[:success]).to be false
        expect(result[:error]).to include('does not exist')
      end
    end

    context 'when the path is already registered' do
      before do
        allow(described_class).to receive(:read_monitors_setting)
          .and_return([{ path: File.expand_path(tmp_dir) }])
      end

      it 'returns success: false with a duplicate error' do
        result = described_class.add_monitor(path: tmp_dir)
        expect(result[:success]).to be false
        expect(result[:error]).to include('already registered')
      end
    end
  end

  # ---------------------------------------------------------------------------
  # .remove_monitor
  # ---------------------------------------------------------------------------

  describe '.remove_monitor' do
    let(:entry) { { path: tmp_dir, label: 'docs', extensions: %w[.md] } }

    before do
      allow(described_class).to receive(:read_monitors_setting).and_return([entry])
      allow(described_class).to receive(:persist_monitors).and_return(true)
    end

    it 'removes by path and returns success: true' do
      result = described_class.remove_monitor(identifier: tmp_dir)
      expect(result[:success]).to be true
      expect(result[:removed][:path]).to eq(tmp_dir)
    end

    it 'removes by label and returns success: true' do
      result = described_class.remove_monitor(identifier: 'docs')
      expect(result[:success]).to be true
      expect(result[:removed][:label]).to eq('docs')
    end

    it 'persists the updated list after removal' do
      expect(described_class).to receive(:persist_monitors).with([]).and_return(true)
      described_class.remove_monitor(identifier: tmp_dir)
    end

    context 'when the identifier is not found' do
      it 'returns success: false' do
        result = described_class.remove_monitor(identifier: 'nonexistent')
        expect(result[:success]).to be false
        expect(result[:error]).to include('not found')
      end
    end
  end

  # ---------------------------------------------------------------------------
  # .list_monitors
  # ---------------------------------------------------------------------------

  describe '.list_monitors' do
    before do
      allow(described_class).to receive(:read_monitors_setting).and_return([])
      allow(described_class).to receive(:read_legacy_corpus_path).and_return(nil)
    end

    it 'returns success: true' do
      result = described_class.list_monitors
      expect(result[:success]).to be true
    end

    it 'includes a monitors key' do
      result = described_class.list_monitors
      expect(result).to have_key(:monitors)
    end

    it 'returns an array for monitors' do
      result = described_class.list_monitors
      expect(result[:monitors]).to be_an(Array)
    end
  end

  # ---------------------------------------------------------------------------
  # .monitor_status
  # ---------------------------------------------------------------------------

  describe '.monitor_status' do
    context 'with no monitors' do
      before do
        allow(described_class).to receive(:read_monitors_setting).and_return([])
        allow(described_class).to receive(:read_legacy_corpus_path).and_return(nil)
      end

      it 'returns success: true' do
        expect(described_class.monitor_status[:success]).to be true
      end

      it 'returns total_monitors of 0' do
        expect(described_class.monitor_status[:total_monitors]).to eq(0)
      end

      it 'returns total_files of 0' do
        expect(described_class.monitor_status[:total_files]).to eq(0)
      end
    end

    context 'with one monitor pointing to a real directory' do
      let(:monitor_entry) { { path: tmp_dir, extensions: %w[.md .txt], label: 'test' } }

      before do
        File.write(File.join(tmp_dir, 'a.md'), '# A')
        File.write(File.join(tmp_dir, 'b.txt'), 'text')
        allow(described_class).to receive(:read_monitors_setting).and_return([monitor_entry])
        allow(described_class).to receive(:read_legacy_corpus_path).and_return(nil)
      end

      it 'returns total_monitors of 1' do
        expect(described_class.monitor_status[:total_monitors]).to eq(1)
      end

      it 'aggregates total_files across monitors' do
        expect(described_class.monitor_status[:total_files]).to eq(2)
      end
    end
  end
end
