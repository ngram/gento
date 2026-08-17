# frozen_string_literal: true

RSpec.describe Slidescraper::Robots do
  def parse(body)
    described_class.parse(body)
  end

  describe "precedence" do
    # The shape Google's robots.txt uses: a blanket Disallow with narrower
    # Allows above it. Read first-match-wins, this file closes the whole site.
    let(:robots) do
      parse(<<~ROBOTS)
        User-agent: *
        Allow: /presentation
        Allow: /document
        Disallow: /templateabuse
        Disallow: /
      ROBOTS
    end

    it "lets the longest matching pattern win" do
      expect(robots).to be_allowed("/presentation/d/abc/htmlpresent")
      expect(robots).to be_allowed("/document/d/abc/edit")
    end

    it "still applies the blanket rule to everything else" do
      expect(robots).not_to be_allowed("/spreadsheets/d/abc")
      expect(robots).not_to be_allowed("/")
    end

    it "prefers the longer of two rules that both match" do
      expect(robots).not_to be_allowed("/templateabuse")
    end

    it "gives a tie to Allow" do
      robots = parse("User-agent: *\nDisallow: /deck\nAllow: /deck\n")

      expect(robots).to be_allowed("/deck")
    end
  end

  describe "patterns" do
    it "treats * as any run of characters" do
      robots = parse("User-agent: *\nDisallow: /slide/*/download\n")

      expect(robots).not_to be_allowed("/slide/AB12CD/download")
      expect(robots).to be_allowed("/slide/AB12CD/embed")
    end

    it "anchors on a trailing $" do
      robots = parse("User-agent: *\nDisallow: /*/followers$\n")

      expect(robots).not_to be_allowed("/example/followers")
      expect(robots).to be_allowed("/example/followers/recent")
    end

    it "matches against the query string as well as the path" do
      robots = parse("User-agent: *\nDisallow: /search?\n")

      expect(robots).not_to be_allowed("/search?q=deck")
      expect(robots).to be_allowed("/search")
    end

    it "reads an empty Disallow as no restriction at all" do
      robots = parse("User-agent: *\nDisallow:\n")

      expect(robots).to be_allowed("/anything")
    end

    it "matches prefixes, not whole paths" do
      robots = parse("User-agent: *\nDisallow: /api/\n")

      expect(robots).not_to be_allowed("/api/decks?url=x")
    end
  end

  describe "groups" do
    let(:robots) do
      parse(<<~ROBOTS)
        User-agent: *
        Disallow: /private/

        User-agent: GreedyBot
        User-agent: OtherBot
        Disallow: /
      ROBOTS
    end

    it "applies the wildcard group to a client no group names" do
      expect(robots.allowed?("/deck", agent: "slidescraper/0.1.0")).to be(true)
      expect(robots.allowed?("/private/x", agent: "slidescraper/0.1.0")).to be(false)
    end

    it "applies a named group to the client it names" do
      expect(robots.allowed?("/deck", agent: "GreedyBot/2.0")).to be(false)
      expect(robots.allowed?("/deck", agent: "OtherBot")).to be(false)
    end

    it "matches the product token case-insensitively" do
      expect(robots.allowed?("/deck", agent: "greedybot/2.0 (+https://example.com)")).to be(false)
    end

    it "obeys the most specific group only" do
      robots = parse(<<~ROBOTS)
        User-agent: *
        Disallow: /

        User-agent: slidescraper
        Disallow: /private/
      ROBOTS

      expect(robots.allowed?("/deck", agent: "slidescraper/0.1.0")).to be(true)
      expect(robots.allowed?("/private/x", agent: "slidescraper/0.1.0")).to be(false)
    end

    # The token runs to the first slash, so the URL in a User-Agent string
    # cannot accidentally opt the client into somebody else's group.
    it "ignores the rest of the User-Agent string when matching" do
      robots = parse("User-agent: github\nDisallow: /\n")

      expect(robots.allowed?("/deck", agent: "slidescraper/0.1.0 (+https://github.com/x)"))
        .to be(true)
    end
  end

  describe "parsing" do
    it "ignores comments and blank lines" do
      robots = parse("# a comment\n\nUser-agent: *   # trailing\nDisallow: /x\n")

      expect(robots).not_to be_allowed("/x")
    end

    it "ignores directives it does not know" do
      robots = parse("Sitemap: https://example.com/sitemap.xml\nHost: example.com\n")

      expect(robots).to be_empty
    end

    it "ignores rules that precede any User-agent line" do
      robots = parse("Disallow: /\nUser-agent: *\nDisallow: /x\n")

      expect(robots).to be_allowed("/deck")
      expect(robots).not_to be_allowed("/x")
    end

    # A page served in place of a robots.txt must not parse into rules. The
    # fetcher rejects it on content type too; this is the second line.
    it "finds nothing to obey in a page of HTML" do
      robots = parse(<<~HTML)
        <!DOCTYPE html>
        <html><head><title>Example</title>
        <script>var a = {"src": "https://example.com/x.js"};</script>
        </head><body>Disallowed: nope</body></html>
      HTML

      expect(robots).to be_empty
      expect(robots).to be_allowed("/anything")
    end

    it "reads Crawl-delay" do
      robots = parse("User-agent: *\nCrawl-delay: 1.5\nDisallow: /x\n")

      expect(robots.crawl_delay).to eq(1.5)
    end

    it "ignores a Crawl-delay that is not a number" do
      robots = parse("User-agent: *\nCrawl-delay: soon\n")

      expect(robots.crawl_delay).to be_nil
    end

    it "starts a new group when a User-agent line follows a rule" do
      robots = parse("User-agent: a\nDisallow: /\nUser-agent: *\nDisallow: /x\n")

      expect(robots.groups.size).to eq(2)
      expect(robots.allowed?("/deck", agent: "slidescraper")).to be(true)
    end
  end

  describe ".allow_all" do
    it "allows everything" do
      expect(described_class.allow_all).to be_allowed("/anything")
    end
  end

  describe ".disallow_all" do
    it "allows nothing and carries the reason why" do
      robots = described_class.disallow_all(reason: "could not read it")

      expect(robots).not_to be_allowed("/")
      expect(robots.reason).to eq("could not read it")
    end
  end
end
