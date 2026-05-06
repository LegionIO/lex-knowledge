# frozen_string_literal: true

module Legion
  module Extensions
    module Knowledge
      module Helpers
        module ApolloModels
          class << self
            def entry
              namespaced_apollo_model(:Entry) || legacy_model(:ApolloEntry)
            end

            def access_log
              namespaced_apollo_model(:AccessLog) || legacy_model(:ApolloAccessLog)
            end

            def entry_available?
              !entry.nil?
            end

            def access_log_available?
              !access_log.nil?
            end

            private

            def namespaced_apollo_model(name)
              return nil unless defined?(Legion::Data::Model::Apollo)
              return nil unless Legion::Data::Model::Apollo.const_defined?(name, false)

              Legion::Data::Model::Apollo.const_get(name, false)
            end

            def legacy_model(name)
              return nil unless defined?(Legion::Data::Model)
              return nil unless Legion::Data::Model.const_defined?(name, false)

              Legion::Data::Model.const_get(name, false)
            end
          end
        end
      end
    end
  end
end
