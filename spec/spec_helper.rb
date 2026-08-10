# frozen_string_literal: true

require "slidescraper"
require "slidescraper/cli"
require_relative "support/stub_fetcher"
require_relative "support/fixtures"

RSpec.configure do |config|
  config.expect_with(:rspec) do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end
  config.mock_with(:rspec) { |mocks| mocks.verify_partial_doubles = true }

  config.include Fixtures

  config.disable_monkey_patching!
  config.warnings = false
  config.order = :random
  Kernel.srand config.seed
end
