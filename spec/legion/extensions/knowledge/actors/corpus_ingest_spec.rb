# frozen_string_literal: true

RSpec.describe Legion::Extensions::Knowledge::Actor::CorpusIngest do
  it 'is defined' do
    expect(described_class).to be_a(Class)
  end

  it 'has a runner_function of ingest_file' do
    instance = described_class.allocate
    expect(instance.runner_function).to eq('ingest_file')
  end

  it 'has runner_class pointing to Ingest runner' do
    instance = described_class.allocate
    expect(instance.runner_class).to eq('Legion::Extensions::Knowledge::Runners::Ingest')
  end
end
