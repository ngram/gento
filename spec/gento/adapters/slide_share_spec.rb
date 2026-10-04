# frozen_string_literal: true

RSpec.describe Gento::Adapters::SlideShare do
  subject(:adapter) { described_class.new(fetcher: fetcher) }

  # The fixture holds a 4-page deck.
  let(:url) { "https://www.slideshare.net/slideshow/example-deck/12345678" }
  let(:fetcher) { StubFetcher.new.stub(url, body: fixture("slide_share", "deck.html")) }

  describe ".handles?" do
    it "claims www and locale subdomains" do
      expect(described_class).to be_handles(url)
      expect(described_class).to be_handles("https://de.slideshare.net/a/b")
    end
  end

  describe "#scrape" do
    it "returns every page in order" do
      deck = adapter.scrape(url)

      expect(deck.page_count).to eq(4)
      expect(deck.slides.map(&:number)).to eq((1..4).to_a)
    end

    it "keeps the widest copy of each page" do
      deck = adapter.scrape(url)

      # This deck publishes page 1 at 2048 and the rest only at 320.
      expect(deck.slides.first.url).to include("-1-2048.jpg")
      expect(deck.slides[1].url).to include("-2-320.jpg")
    end

    it "excludes images on the same CDN that are not pages" do
      deck = adapter.scrape(url)

      expect(deck.slides.map(&:url)).to all(exclude_substring("profile-photo"))
    end

    it "reads metadata from OpenGraph and JSON-LD" do
      deck = adapter.scrape(url)

      expect(deck.title).to eq("Example Presentation")
      expect(deck.author).to eq("Example Author")
      expect(deck.published_at).to start_with("2019-01-02")
      expect(deck.provider).to eq("slide_share")
    end

    it "counts each page once" do
      deck = adapter.scrape(url)

      expect(deck.slides.map(&:url).uniq.size).to eq(4)
    end
  end

  describe "the bot challenge" do
    # SlideShare answers a client it does not trust with a JavaScript
    # interstitial rather than the deck. Naming it turns an otherwise baffling
    # "no slides found" into something actionable.
    let(:fetcher) { StubFetcher.new.stub(url, body: fixture("slide_share", "challenge.html")) }

    it "is reported as itself, not as an empty deck" do
      expect { adapter.scrape(url) }
        .to raise_error(Gento::ExtractionError, /bot challenge/)
    end

    it "points at the fetcher seam as the way past it" do
      expect { adapter.scrape(url) }
        .to raise_error(Gento::ExtractionError, /Gento::Fetcher/)
    end
  end
end
