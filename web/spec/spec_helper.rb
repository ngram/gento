# frozen_string_literal: true

ENV["APP_ENV"] = "test"
ENV["RACK_ENV"] = "test"

require "rack/test"
require_relative "../app"

RSpec.configure do |config|
  config.include Rack::Test::Methods

  config.before do
    Slidescraper::Web::App::CACHE.clear
  end

  config.disable_monkey_patching!
  config.order = :random
end
