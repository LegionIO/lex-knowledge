# frozen_string_literal: true

module Legion
  module Extensions
    module Knowledge
      module Transport
        module Messages
          class IngestMessage < Legion::Transport::Message
            def exchange_name = 'knowledge'
            def routing_key = 'knowledge.ingest'
          end
        end
      end
    end
  end
end
