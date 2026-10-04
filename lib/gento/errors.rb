# frozen_string_literal: true

module Gento
  # Base class for every error raised by this library. Callers that just want
  # "did it work?" can rescue this one class.
  class Error < StandardError; end

  # The given URL is not a URL we know how to handle.
  class UnsupportedURLError < Error
    attr_reader :url

    def initialize(url)
      @url = url
      super("no adapter registered for #{url.inspect}")
    end
  end

  # The URL looked supported, but the remote document did not contain the
  # slide data we expected. Usually means the site changed its markup.
  class ExtractionError < Error; end

  # Something went wrong while talking to the remote host.
  class FetchError < Error
    attr_reader :url, :status

    def initialize(message, url: nil, status: nil)
      @url = url
      @status = status
      super(message)
    end
  end

  # The remote host answered, but with a non-success status.
  class ResponseError < FetchError; end

  # We followed more redirects than the fetcher allows.
  class TooManyRedirectsError < FetchError; end

  # The host's robots.txt does not allow this client to fetch this path — or
  # could not be read, which comes to the same thing.
  #
  # A FetchError because it is a request that did not happen, which also means
  # an optional extra like an oEmbed lookup degrades instead of failing the
  # whole scrape.
  class RobotsDisallowedError < FetchError; end
end
