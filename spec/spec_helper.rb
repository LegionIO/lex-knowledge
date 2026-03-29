# frozen_string_literal: true

require 'bundler/setup'
require 'tmpdir'
require 'fileutils'

module Legion
  module Extensions
    module Helpers
      module Lex; end
    end

    module Core; end
  end

  module Extensions
    module Actors
      class Every; end
      class Subscription; end
    end
  end

  module Logging
    def self.debug(msg = nil); end
    def self.info(msg = nil); end
    def self.warn(msg = nil); end
    def self.error(msg = nil); end
    def self.fatal(msg = nil); end
  end

  module Transport
    class Exchange; end
    class Queue; end
    class Message; end
  end
end

require 'legion/extensions/knowledge'

RSpec.configure do |config|
  config.example_status_persistence_file_path = '.rspec_status'
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.order = :random
  Kernel.srand config.seed
end
