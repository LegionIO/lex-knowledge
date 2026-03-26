# frozen_string_literal: true

RSpec.describe Legion::Extensions::Knowledge::Actor::CorpusWatcher do
  let(:instance) { described_class.allocate }
  let(:monitor)  { { path: '/tmp/docs', extensions: %w[.md .txt], label: 'docs' } }

  it 'is defined' do
    expect(described_class).to be_a(Class)
  end

  it 'has runner_class pointing to Runners::Ingest' do
    expect(instance.runner_class).to eq('Legion::Extensions::Knowledge::Runners::Ingest')
  end

  it 'has a runner_function of ingest_corpus' do
    expect(instance.runner_function).to eq('ingest_corpus')
  end

  it 'has a configurable interval' do
    expect(instance.respond_to?(:every_interval)).to be true
  end

  it 'defaults interval to 300' do
    expect(instance.every_interval).to eq(300)
  end

  describe '#enabled?' do
    it 'returns true when monitors are present' do
      allow(Legion::Extensions::Knowledge::Runners::Monitor)
        .to receive(:resolve_monitors).and_return([monitor])
      expect(instance.enabled?).to be true
    end

    it 'returns false when no monitors are configured' do
      allow(Legion::Extensions::Knowledge::Runners::Monitor)
        .to receive(:resolve_monitors).and_return([])
      expect(instance.enabled?).to be false
    end

    it 'returns false when resolve_monitors raises' do
      allow(Legion::Extensions::Knowledge::Runners::Monitor)
        .to receive(:resolve_monitors).and_raise(StandardError)
      expect(instance.enabled?).to be false
    end
  end

  describe '#args' do
    it 'returns monitors hash from resolve_monitors' do
      allow(Legion::Extensions::Knowledge::Runners::Monitor)
        .to receive(:resolve_monitors).and_return([monitor])
      expect(instance.args).to eq({ monitors: [monitor] })
    end

    it 'returns empty monitors array when none configured' do
      allow(Legion::Extensions::Knowledge::Runners::Monitor)
        .to receive(:resolve_monitors).and_return([])
      expect(instance.args).to eq({ monitors: [] })
    end
  end

  describe '#resolve_monitors (private delegation)' do
    it 'delegates to Runners::Monitor.resolve_monitors' do
      allow(Legion::Extensions::Knowledge::Runners::Monitor)
        .to receive(:resolve_monitors).and_return([monitor])
      expect(instance.send(:resolve_monitors)).to eq([monitor])
    end

    it 'returns empty array when Runners::Monitor raises' do
      allow(Legion::Extensions::Knowledge::Runners::Monitor)
        .to receive(:resolve_monitors).and_raise(StandardError)
      expect(instance.send(:resolve_monitors)).to eq([])
    end
  end
end
