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
  #
  # Every request goes through the host's robots.txt unless robots: false is
  # passed. This holds for an injected fetcher too — the point of the check is
  # the request, not who makes it.
  class Client
    attr_reader :fetcher, :registry

    def initialize(fetcher: nil, registry: nil, robots: true)
      @registry = registry || Registry.default
      @fetcher = wrap(fetcher || NetHttpFetcher.new, robots: robots)
    end

    def robots?
      fetcher.is_a?(RobotsFetcher)
    end

    # @raise [UnsupportedURLError] when no adapter claims the URL
    # @raise [RobotsDisallowedError] when robots.txt does not allow the fetch
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

    private

    # A fetcher that already checks robots.txt is left alone, so passing one
    # in explicitly does not stack two checks.
    def wrap(fetcher, robots:)
      return fetcher if !robots || fetcher.is_a?(RobotsFetcher)

      RobotsFetcher.new(fetcher)
    end
  end
end
