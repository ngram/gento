# frozen_string_literal: true

RSpec.describe Slidescraper::Adapters::Docswell do
  subject(:adapter) { described_class.new(fetcher: fetcher) }

  # Captured from a real 57-page deck.
  let(:url) { "https://www.docswell.com/s/Akira_Ikeda/Z7N1RD-2026-07-24-JaSST26Hokkaido" }
  let(:embed_url) { "https://www.docswell.com/slide/Z7N1RD/embed" }
  let(:fetcher) do
    StubFetcher.new
               .stub(url, body: fixture("docswell", "deck.html"))
               .stub(embed_url, body: fixture("docswell", "embed.html"))
               .stub(%r{/service/oembed}, body: fixture("docswell", "oembed.json"))
  end

  describe "#scrape" do
    it "reads the whole deck from the embed view" do
      deck = adapter.scrape(url)

      expect(deck.page_count).to eq(57)
      expect(fetcher).to be_requested(embed_url)
    end

    it "collapses the thumbnail of each page into one slide" do
      deck = adapter.scrape(url)

      expect(deck.slides.map(&:url)).to all(satisfy { |url| !url.include?("width=") })
      expect(deck.slides.map(&:url).uniq.size).to eq(57)
    end

    it "orders pages as the deck presents them" do
      deck = adapter.scrape(url)

      # og:image on the deck page is the cover, so it must come first.
      expect(deck.slides.first.url).to eq("https://bcdn.docswell.com/page/G75M4Z3P74.jpg")
    end

    it "excludes site chrome served from the same CDN" do
      deck = adapter.scrape(url)

      expect(deck.slides.map(&:url)).to all(include("/page/"))
    end

    it "reads metadata from OpenGraph" do
      deck = adapter.scrape(url)

      expect(deck.title).to include("AI")
      expect(deck.author).to start_with("Akira Ikeda")
      expect(deck.provider).to eq("docswell")
    end

    it "raises ExtractionError when the embed view cannot be found" do
      fetcher = StubFetcher.new.stub(url, body: "<html><head><title>x</title></head></html>")

      expect { described_class.new(fetcher: fetcher).scrape(url) }
        .to raise_error(Slidescraper::ExtractionError, /embed view/)
    end
  end
end
