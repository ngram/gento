# frozen_string_literal: true

RSpec.describe Slidescraper::Adapters::Docswell do
  subject(:adapter) { described_class.new(fetcher: fetcher) }

  # The fixture holds a 5-page deck, of which the deck page itself renders
  # only the first two.
  let(:url) { "https://www.docswell.com/s/example/EX7A2B-example" }
  let(:embed_url) { "https://www.docswell.com/slide/EX7A2B/embed" }
  let(:fetcher) do
    StubFetcher.new
               .stub(url, body: fixture("docswell", "deck.html"))
               .stub(embed_url, body: fixture("docswell", "embed.html"))
               .stub(%r{/service/oembed}, body: fixture("docswell", "oembed.json"))
  end

  describe "#scrape" do
    it "reads the whole deck from the embed view" do
      deck = adapter.scrape(url)

      expect(deck.page_count).to eq(5)
      expect(fetcher).to be_requested(embed_url)
    end

    it "collapses the thumbnail of each page into one slide" do
      deck = adapter.scrape(url)

      expect(deck.slides.map(&:url)).to all(exclude_substring("width="))
      expect(deck.slides.map(&:url).uniq.size).to eq(5)
    end

    it "orders pages as the deck presents them" do
      deck = adapter.scrape(url)

      # og:image on the deck page is the cover, so it must come first.
      expect(deck.slides.first.url).to eq("https://bcdn.docswell.com/page/AAAA111111.jpg")
    end

    it "excludes site chrome served from the same CDN" do
      deck = adapter.scrape(url)

      expect(deck.slides.map(&:url)).to all(include("/page/"))
    end

    it "reads metadata from OpenGraph and oEmbed" do
      deck = adapter.scrape(url)

      expect(deck.title).to eq("サンプル資料")
      expect(deck.author).to eq("サンプル著者")
      expect(deck.provider).to eq("docswell")
    end

    it "raises ExtractionError when the embed view cannot be found" do
      fetcher = StubFetcher.new.stub(url, body: "<html><head><title>x</title></head></html>")

      expect { described_class.new(fetcher: fetcher).scrape(url) }
        .to raise_error(Slidescraper::ExtractionError, /embed view/)
    end
  end
end
