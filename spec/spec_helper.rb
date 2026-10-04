# frozen_string_literal: true

require "gento"
require "gento/cli"
require_relative "support/stub_fetcher"
require_relative "support/fixtures"

# RSpec has no negated `include` that composes inside `all`.
RSpec::Matchers.define :exclude_substring do |expected|
  match { |actual| !actual.to_s.include?(expected) }
  failure_message { |actual| "expected #{actual.inspect} not to include #{expected.inspect}" }
end

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
