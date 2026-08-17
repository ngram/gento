# frozen_string_literal: true

RSpec.describe Slidescraper::RobotsFetcher do
  subject(:fetcher) { described_class.new(inner, user_agent: "slidescraper/1.0") }

  let(:deck_url) { "https://example.com/decks/1" }
  let(:robots_url) { "https://example.com/robots.txt" }
  let(:inner) { StubFetcher.new.stub(deck_url, body: "<html></html>") }

  def allow_robots(body)
    inner.stub(robots_url, body: body, headers: { "content-type" => "text/plain" })
  end

  describe "#get" do
    it "passes the request through when robots.txt allows it" do
      allow_robots("User-agent: *\nDisallow: /private/\n")

      expect(fetcher.get(deck_url).status).to eq(200)
      expect(inner).to be_requested(deck_url)
    end

    it "refuses the request when robots.txt disallows it" do
      allow_robots("User-agent: *\nDisallow: /decks/\n")

      expect { fetcher.get(deck_url) }
        .to raise_error(Slidescraper::RobotsDisallowedError, %r{disallows /decks/1})
      expect(inner).not_to be_requested(deck_url)
    end

    it "names the escape hatch in the refusal" do
      allow_robots("User-agent: *\nDisallow: /\n")

      expect { fetcher.get(deck_url) }
        .to raise_error(Slidescraper::RobotsDisallowedError, /robots: false/)
    end

    it "obeys a group naming this client over the wildcard group" do
      allow_robots("User-agent: *\nDisallow: /\n\nUser-agent: slidescraper\nDisallow: /private/\n")

      expect(fetcher.get(deck_url).status).to eq(200)
    end

    it "reads robots.txt once per host" do
      allow_robots("User-agent: *\nDisallow: /private/\n")

      3.times { fetcher.get(deck_url) }

      expect(inner.requests.count(robots_url)).to eq(1)
    end

    it "reads robots.txt separately for each host" do
      allow_robots("User-agent: *\nDisallow: /private/\n")
      inner.stub("https://other.example/robots.txt", body: "User-agent: *\nDisallow: /\n",
                                                     headers: { "content-type" => "text/plain" })

      expect { fetcher.get("https://other.example/decks/1") }
        .to raise_error(Slidescraper::RobotsDisallowedError)
      expect(fetcher.get(deck_url).status).to eq(200)
    end

    it "checks the query string, not just the path" do
      allow_robots("User-agent: *\nDisallow: /decks/1?export\n")

      expect(fetcher.get(deck_url).status).to eq(200)
      expect { fetcher.get("#{deck_url}?export=png") }
        .to raise_error(Slidescraper::RobotsDisallowedError)
    end
  end

  describe "when there is no robots.txt to read" do
    it "allows everything on a 404" do
      expect(fetcher.get(deck_url).status).to eq(200)
    end

    it "allows everything on any other 4xx" do
      inner.stub(robots_url, body: "no", status: 403)

      expect(fetcher.get(deck_url).status).to eq(200)
    end

    it "finds nothing to obey in a page served in place of a robots.txt" do
      inner.stub(robots_url, body: "<html><body>nothing here</body></html>",
                             headers: { "content-type" => "text/html; charset=utf-8" })

      expect(fetcher.get(deck_url).status).to eq(200)
    end
  end

  # Speaker Deck answers /robots.txt through its HTML layout unless asked for
  # plain text. Judging the response by its content type would throw the real
  # rules away, so the body is parsed either way.
  describe "when the host serves a real robots.txt as HTML" do
    it "asks for plain text" do
      allow_robots("User-agent: *\nDisallow: /private/\n")

      fetcher.get(deck_url)

      expect(inner.headers_for(robots_url)).to include("accept" => "text/plain")
    end

    it "obeys the directives anyway" do
      inner.stub(robots_url, body: "<html><body>\nUser-agent: *\nDisallow: /decks/\n</body></html>",
                             headers: { "content-type" => "text/html; charset=utf-8" })

      expect { fetcher.get(deck_url) }
        .to raise_error(Slidescraper::RobotsDisallowedError)
    end
  end

  describe "when robots.txt cannot be read" do
    # RFC 9309 §2.3.1.4: not being able to read robots.txt is not permission.
    it "refuses on a 5xx" do
      inner.stub(robots_url, body: "boom", status: 503)

      expect { fetcher.get(deck_url) }
        .to raise_error(Slidescraper::RobotsDisallowedError, /could not read/)
    end

    it "refuses on 429, which asks us to come back later" do
      inner.stub(robots_url, body: "slow down", status: 429)

      expect { fetcher.get(deck_url) }
        .to raise_error(Slidescraper::RobotsDisallowedError, /429/)
    end

    it "refuses when the request fails outright" do
      failing = Class.new(Slidescraper::Fetcher) do
        def get(url, headers: {}) # rubocop:disable Lint/UnusedMethodArgument
          raise Slidescraper::FetchError, "timed out" if url.to_s.end_with?("/robots.txt")

          Slidescraper::Response.new(status: 200, body: "", url: url.to_s)
        end
      end.new

      expect { described_class.new(failing).get(deck_url) }
        .to raise_error(Slidescraper::RobotsDisallowedError, /timed out/)
    end
  end

  describe "#crawl_delay" do
    it "reports what the host asks for" do
      allow_robots("User-agent: *\nCrawl-delay: 2\nDisallow: /private/\n")

      expect(fetcher.crawl_delay(deck_url)).to eq(2.0)
    end

    it "is nil when the host asks for nothing" do
      allow_robots("User-agent: *\nDisallow: /private/\n")

      expect(fetcher.crawl_delay(deck_url)).to be_nil
    end
  end

  describe "the wrapped fetcher" do
    it "inherits its User-Agent when none is given" do
      inner = Slidescraper::NetHttpFetcher.new(user_agent: "custom/9")

      expect(described_class.new(inner).user_agent).to eq("custom/9")
    end

    it "tolerates a fetcher that has no User-Agent to inherit" do
      expect(described_class.new(StubFetcher.new).user_agent).to be_nil
    end

    it "passes a non-HTTP URL straight through, for the fetcher to judge" do
      inner = StubFetcher.new.stub("ftp://example.com/x", body: "")

      expect(described_class.new(inner).get("ftp://example.com/x").status).to eq(200)
    end
  end
end
