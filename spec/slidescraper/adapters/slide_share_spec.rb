# frozen_string_literal: true

RSpec.describe Slidescraper::Adapters::SlideShare do
  subject(:adapter) { described_class.new(fetcher: fetcher) }

  # Captured from a real 11-page deck.
  let(:url) { "https://www.slideshare.net/slideshow/pr-strategy-deck/70491980" }
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

      expect(deck.page_count).to eq(11)
      expect(deck.slides.map(&:number)).to eq((1..11).to_a)
    end

    it "keeps the widest copy of each page" do
      deck = adapter.scrape(url)

      # This deck publishes page 1 at 2048 and the rest only at 320.
      expect(deck.slides.first.url).to include("-1-2048.jpg")
      expect(deck.slides[1].url).to include("-2-320.jpg")
    end

    it "reads metadata from OpenGraph and JSON-LD" do
      deck = adapter.scrape(url)

      expect(deck.title).to eq("PR Strategy Deck")
      expect(deck.author).to eq("Tayub R")
      expect(deck.published_at).to start_with("2016-12-28")
      expect(deck.provider).to eq("slide_share")
    end

    it "counts each page once" do
      deck = adapter.scrape(url)

      expect(deck.slides.map(&:url).uniq.size).to eq(11)
    end
  end

  describe "the bot challenge" do
    # SlideShare intermittently answers with a JavaScript interstitial rather
    # than the deck, most readily under bursty access. Naming it turns an
    # otherwise baffling "no slides found" into something actionable.
    let(:fetcher) { StubFetcher.new.stub(url, body: fixture("slide_share", "challenge.html")) }

    it "is reported as itself, not as an empty deck" do
      expect { adapter.scrape(url) }
        .to raise_error(Slidescraper::ExtractionError, /bot challenge/)
    end

    it "points at the fetcher seam as the way past it" do
      expect { adapter.scrape(url) }
        .to raise_error(Slidescraper::ExtractionError, /Slidescraper::Fetcher/)
    end
  end
end
