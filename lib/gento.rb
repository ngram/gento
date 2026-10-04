# frozen_string_literal: true

require_relative "gento/version"
require_relative "gento/errors"
require_relative "gento/charset"
require_relative "gento/entities"
require_relative "gento/html"
require_relative "gento/response"
require_relative "gento/fetcher"
require_relative "gento/robots"
require_relative "gento/robots_fetcher"
require_relative "gento/slide"
require_relative "gento/deck"
require_relative "gento/adapters/base"
require_relative "gento/adapters/speaker_deck"
require_relative "gento/adapters/slide_share"
require_relative "gento/adapters/docswell"
require_relative "gento/adapters/google_slides"
require_relative "gento/registry"
require_relative "gento/client"

# Turns a slide-sharing URL into the ordered list of page images behind it.
#
# Supports Speaker Deck, SlideShare, Docswell and public Google Slides decks.
# The gem is pure Ruby with no runtime dependencies, so it runs anywhere CRuby
# does — including slim containers and ruby.wasm.
module Gento
  class << self
    # Convenience wrapper around Client#fetch for one-off calls.
    #
    # robots: false skips the robots.txt check, which is on by default.
    def fetch(url, fetcher: nil, registry: nil, robots: true)
      Client.new(fetcher: fetcher, registry: registry, robots: robots).fetch(url)
    end

    def supports?(url)
      Registry.default.supports?(url)
    end

    def providers
      Registry.default.providers
    end
  end
end
