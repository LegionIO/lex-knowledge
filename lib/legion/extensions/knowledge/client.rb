# frozen_string_literal: true

module Legion
  module Extensions
    module Knowledge
      class Client
        include Runners::Ingest
        include Runners::Query
        include Runners::Corpus
        include Runners::Maintenance
        include Runners::Monitor
      end
    end
  end
end
