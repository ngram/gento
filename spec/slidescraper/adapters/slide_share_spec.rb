# frozen_string_literal: true

RSpec.describe Slidescraper::Adapters::SlideShare do
  subject(:adapter) { described_class.new(fetcher: fetcher) }

  let(:url) { "https://www.slideshare.net/ngram/slide-viewer" }
  let(:fetcher) { StubFetcher.new.stub(url, body: fixture("slide_share", "deck.html")) }

  describe ".handles?" do
    it "claims www and locale subdomains" do
      expect(described_class).to be_handles(url)
      expect(described_class).to be_handles("https://de.slideshare.net/ngram/slide-viewer")
    end
  end

  describe "#scrape" do
    it "keeps the widest copy of each page, in page order" do
      deck = adapter.scrape(url)

      expect(deck.slides.map(&:url)).to eq(
        [
          "https://image.slidesharecdn.com/deckkey-181008/85/slide-viewer-1-2048.jpg",
          "https://image.slidesharecdn.com/deckkey-181008/85/slide-viewer-2-2048.jpg",
          "https://image.slidesharecdn.com/deckkey-181008/95/slide-viewer-3-638.jpg"
        ]
      )
    end

    it "reads metadata from OpenGraph and JSON-LD" do
      deck = adapter.scrape(url)

      expect(deck.title).to eq("Building a comfortable slide viewer")
      expect(deck.author).to eq("ngram")
      expect(deck.published_at).to eq("2018-10-08")
    end

    it "drops CDN images that are not paged slides" do
      deck = adapter.scrape(url)

      expect(deck.slides.map(&:url)).to all(include("slide-viewer-"))
      expect(deck.page_count).to eq(3)
    end
  end
end
