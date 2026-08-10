# frozen_string_literal: true

RSpec.describe Slidescraper::Adapters::Docswell do
  subject(:adapter) { described_class.new(fetcher: fetcher) }

  let(:url) { "https://www.docswell.com/s/ngram/ZX9K2P-slide-scraping" }
  let(:fetcher) { StubFetcher.new.stub(url, body: fixture("docswell", "deck.html")) }

  describe "#scrape" do
    it "returns the pages in order" do
      deck = adapter.scrape(url)

      expect(deck.slides.map(&:url)).to eq(
        (1..4).map { |n| "https://media.docswell.com/s/ngram/ZX9K2P/slide_#{n}.jpg" }
      )
    end

    it "takes the image host from og:image and so ignores site assets" do
      deck = adapter.scrape(url)

      expect(deck.slides.map(&:url)).to all(start_with("https://media.docswell.com/"))
      expect(deck.page_count).to eq(4)
    end

    it "reads metadata from OpenGraph" do
      deck = adapter.scrape(url)

      expect(deck.title).to eq("スライドスクレイピング入門")
      expect(deck.author).to eq("ngram")
      expect(deck.provider).to eq("docswell")
    end

    it "raises ExtractionError when the page holds no slide images" do
      fetcher = StubFetcher.new.stub(url, body: "<html><head><title>x</title></head></html>")

      expect { described_class.new(fetcher: fetcher).scrape(url) }
        .to raise_error(Slidescraper::ExtractionError)
    end
  end
end
