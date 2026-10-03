# frozen_string_literal: true

require "uri"

module Slidescraper
  # A Fetcher that consults robots.txt before letting a request through.
  #
  # It wraps another fetcher rather than living inside one, so it applies to
  # every request an adapter makes — the deck page, the oEmbed endpoint, the
  # embed view — and works just as well over an injected fetcher as over the
  # net/http one.
  #
  # On by default. `Slidescraper.scrape(url, robots: false)` turns it off; the
  # caller then owns whatever that implies.
  #
  # One gap: the wrapped fetcher follows redirects itself, so a redirect into
  # a disallowed path is not caught. Checking that needs a per-hop callback in
  # the fetcher, which is not worth the interface it would add.
  class RobotsFetcher < Fetcher
    ROBOTS_PATH = "/robots.txt"
    # Speaker Deck serves its robots.txt through the site's HTML layout unless
    # this header asks for plain text, so it is load-bearing rather than
    # politeness. The body is parsed whatever content type comes back: a page
    # that is not a robots.txt yields no directives anyway, and refusing on
    # content type alone would throw away real rules from a host that answers
    # in HTML.
    PLAIN_TEXT = { "accept" => "text/plain" }.freeze
    DEFAULT_PORTS = { "http" => 80, "https" => 443 }.freeze

    attr_reader :fetcher, :user_agent

    def initialize(fetcher, user_agent: nil)
      @fetcher = fetcher
      @user_agent = user_agent || inherited_user_agent(fetcher)
      @robots = {}
      super()
    end

    def get(url, headers: {})
      uri = coerce_uri(url)
      guard!(uri) if uri

      fetcher.get(url, headers: headers)
    end

    # The Crawl-delay the host asks for, in seconds, or nil.
    #
    # Not enforced here: one scrape is a handful of requests, and sleeping
    # inside a fetcher would surprise a caller who already paces its own work.
    # Exposed so a caller doing more than one deck can honour it.
    def crawl_delay(url)
      uri = coerce_uri(url)
      return nil unless uri

      robots_for(uri).crawl_delay(agent: user_agent)
    end

    def robots_for(uri)
      @robots[origin(uri)] ||= load_robots(origin(uri))
    end

    private

    def guard!(uri)
      robots = robots_for(uri)
      path = request_path(uri)
      return if robots.allowed?(path, agent: user_agent)

      raise RobotsDisallowedError.new(refusal(uri, path, robots), url: uri.to_s)
    end

    def refusal(uri, path, robots)
      cause = robots.reason || "#{origin(uri)}#{ROBOTS_PATH} disallows #{path}"

      "#{cause} for #{user_agent_label}. " \
        "Pass robots: false to scrape it anyway, and take responsibility for doing so."
    end

    def user_agent_label
      user_agent.to_s.empty? ? "this client" : user_agent.inspect
    end

    def load_robots(origin)
      Robots.parse(fetcher.get("#{origin}#{ROBOTS_PATH}", headers: PLAIN_TEXT).body)
    rescue ResponseError => e
      absent?(e.status) ? Robots.allow_all : unreachable(origin, "responded #{e.status}")
    rescue FetchError => e
      unreachable(origin, e.message)
    end

    # 4xx is the host saying there is no robots.txt, which RFC 9309 reads as
    # "help yourself". 429 is it saying to come back later, which is not the
    # same thing.
    def absent?(status)
      status.to_i.between?(400, 499) && status.to_i != 429
    end

    def unreachable(origin, detail)
      Robots.disallow_all(reason: "could not read #{origin}#{ROBOTS_PATH} (#{detail}), " \
                                  "so there is no permission to rely on")
    end

    def origin(uri)
      port = ":#{uri.port}" unless uri.port == DEFAULT_PORTS[uri.scheme]

      "#{uri.scheme}://#{uri.host}#{port}"
    end

    # Rules match against the path and query together.
    def request_path(uri)
      path = uri.path.to_s.empty? ? "/" : uri.path
      uri.query ? "#{path}?#{uri.query}" : path
    end

    def coerce_uri(url)
      uri = url.is_a?(URI) ? url : URI.parse(url.to_s)
      uri.is_a?(URI::HTTP) ? uri : nil
    rescue URI::InvalidURIError
      nil
    end

    def inherited_user_agent(fetcher)
      fetcher.user_agent if fetcher.respond_to?(:user_agent)
    end
  end
end
