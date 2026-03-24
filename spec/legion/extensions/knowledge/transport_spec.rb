# frozen_string_literal: true

RSpec.describe 'Transport layer' do
  it 'defines Knowledge exchange' do
    expect(Legion::Extensions::Knowledge::Transport::Exchanges::Knowledge).to be_a(Class)
  end

  it 'defines Ingest queue' do
    expect(Legion::Extensions::Knowledge::Transport::Queues::Ingest).to be_a(Class)
  end

  it 'defines IngestMessage' do
    expect(Legion::Extensions::Knowledge::Transport::Messages::IngestMessage).to be_a(Class)
  end
end
