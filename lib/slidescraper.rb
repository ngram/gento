# frozen_string_literal: true

require_relative "slidescraper/version"
require_relative "slidescraper/errors"
require_relative "slidescraper/charset"
require_relative "slidescraper/entities"
require_relative "slidescraper/html"
require_relative "slidescraper/response"
require_relative "slidescraper/fetcher"
require_relative "slidescraper/robots"
require_relative "slidescraper/robots_fetcher"
require_relative "slidescraper/slide"
require_relative "slidescraper/deck"
require_relative "slidescraper/adapters/base"
require_relative "slidescraper/adapters/speaker_deck"
require_relative "slidescraper/adapters/slide_share"
require_relative "slidescraper/adapters/docswell"
require_relative "slidescraper/adapters/google_slides"
require_relative "slidescraper/registry"
require_relative "slidescraper/client"

# Turns a slide-sharing URL into the ordered list of page images behind it.
#
# Supports Speaker Deck, SlideShare, Docswell and public Google Slides decks.
# The gem is pure Ruby with no runtime dependencies, so it runs anywhere CRuby
# does — including slim containers and ruby.wasm.
module Slidescraper
  class << self
    # Convenience wrapper around Client#scrape for one-off calls.
    #
    # robots: false skips the robots.txt check, which is on by default.
    def scrape(url, fetcher: nil, registry: nil, robots: true)
      Client.new(fetcher: fetcher, registry: registry, robots: robots).scrape(url)
    end

    def supports?(url)
      Registry.default.supports?(url)
    end

    def providers
      Registry.default.providers
    end
  end
end
