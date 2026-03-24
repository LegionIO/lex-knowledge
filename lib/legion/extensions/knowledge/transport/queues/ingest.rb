# frozen_string_literal: true

module Legion
  module Extensions
    module Knowledge
      module Transport
        module Queues
          class Ingest < Legion::Transport::Queue
            def queue_name = 'knowledge.ingest'
            def exchange_name = 'knowledge'
            def routing_key = 'knowledge.ingest'
            def durable = true
          end
        end
      end
    end
  end
end
