# frozen_string_literal: true

module Legion
  module Extensions
    module Knowledge
      module Transport
        module Exchanges
          class Knowledge < Legion::Transport::Exchange
            def exchange_name = 'knowledge'
            def type = 'topic'
            def durable = true
          end
        end
      end
    end
  end
end
