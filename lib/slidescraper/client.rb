# frozen_string_literal: true

module Slidescraper
  # The entry point: give it a slide URL, get a Deck back.
  #
  #   client = Slidescraper::Client.new
  #   deck = client.scrape("https://speakerdeck.com/user/talk")
  #   deck.slides.map(&:url)
  #
  # Both collaborators are injectable: swap the fetcher to run on a host with
  # its own HTTP stack, swap the registry to limit or extend the supported
  # sites.
  class Client
    attr_reader :fetcher, :registry

    def initialize(fetcher: nil, registry: nil)
      @fetcher = fetcher || NetHttpFetcher.new
      @registry = registry || Registry.default
    end

    # @raise [UnsupportedURLError] when no adapter claims the URL
    # @raise [FetchError] when the remote host cannot be reached
    # @raise [ExtractionError] when the page held no slides
    # @return [Deck]
    def scrape(url)
      adapter = registry.find(url)
      raise UnsupportedURLError, url unless adapter

      adapter.new(fetcher: fetcher).scrape(url.to_s)
    end

    def supports?(url)
      registry.supports?(url)
    end
  end
end
