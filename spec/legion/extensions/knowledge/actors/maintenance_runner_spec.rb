# frozen_string_literal: true

RSpec.describe Legion::Extensions::Knowledge::Actor::MaintenanceRunner do
  it 'is defined' do
    expect(described_class).to be_a(Class)
  end

  it 'targets the health runner function' do
    instance = described_class.allocate
    expect(instance.runner_function).to eq('health')
  end

  it 'targets the Maintenance runner class' do
    instance = described_class.allocate
    expect(instance.runner_class).to eq('Legion::Extensions::Knowledge::Runners::Maintenance')
  end

  it 'defaults interval to 21600 seconds (6 hours)' do
    instance = described_class.allocate
    expect(instance.every_interval).to eq(21_600)
  end

  it 'responds to enabled?' do
    instance = described_class.allocate
    expect(instance).to respond_to(:enabled?)
  end

  it 'is not enabled when no corpus_path is configured' do
    instance = described_class.allocate
    expect(instance.enabled?).to be false
  end
end
