# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions::Knowledge::Transport::Messages::MonitorReload do
  it 'is defined' do
    expect(described_class).to be_a(Class)
  end

  it 'has exchange_name of knowledge' do
    instance = described_class.allocate
    expect(instance.exchange_name).to eq('knowledge')
  end

  it 'has routing_key of knowledge.monitor.reload' do
    instance = described_class.allocate
    expect(instance.routing_key).to eq('knowledge.monitor.reload')
  end
end
