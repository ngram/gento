# frozen_string_literal: true

# An in-memory Fetcher for the specs.
#
# Because the library takes its HTTP client by injection, the test suite needs
# no HTTP stubbing library and never opens a socket — which is also what makes
# it runnable in this repo's offline CI.
class StubFetcher < Slidescraper::Fetcher
  Stub = Struct.new(:status, :body, :headers, keyword_init: true)

  attr_reader :requests

  def initialize(stubs = {})
    @stubs = {}
    @requests = []
    stubs.each { |url, body| stub(url, body: body) }
    super()
  end

  def stub(url, body:, status: 200, headers: { "content-type" => "text/html" })
    @stubs[url] = Stub.new(status: status, body: body, headers: headers)
    self
  end

  def get(url, headers: {}) # rubocop:disable Lint/UnusedMethodArgument
    url = url.to_s
    @requests << url
    stub = lookup(url)

    unless stub.status.between?(200, 299)
      raise Slidescraper::ResponseError.new("#{url} responded #{stub.status}",
                                            url: url, status: stub.status)
    end

    Slidescraper::Response.new(status: stub.status, body: stub.body, url: url, headers: stub.headers)
  end

  def requested?(url)
    @requests.any? { |requested| url.is_a?(Regexp) ? requested.match?(url) : requested == url }
  end

  private

  # An unstubbed URL is a 404 rather than a silent nil, so a spec that forgets
  # a stub fails the way the real world would.
  def lookup(url)
    stub = @stubs[url] || @stubs.find { |key, _| key.is_a?(Regexp) && url.match?(key) }&.last
    return stub if stub

    raise Slidescraper::ResponseError.new("#{url} responded 404", url: url, status: 404)
  end
end
