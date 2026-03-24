# frozen_string_literal: true

RSpec.describe Legion::Extensions::Knowledge::Actor::CorpusWatcher do
  it 'is defined' do
    expect(described_class).to be_a(Class)
  end

  it 'has a runner_function of ingest_corpus' do
    instance = described_class.allocate
    expect(instance.runner_function).to eq('ingest_corpus')
  end

  it 'has a configurable interval' do
    instance = described_class.allocate
    expect(instance.respond_to?(:every_interval)).to be true
  end

  it 'defaults interval to 300' do
    instance = described_class.allocate
    expect(instance.every_interval).to eq(300)
  end
end
