# frozen_string_literal: true

RSpec.describe Slidescraper::Adapters::GoogleSlides do
  subject(:adapter) { described_class.new(fetcher: fetcher) }

  let(:id) { "1AbCdEfGhIjKlMnOpQrStUvWxYz0123456789" }
  let(:url) { "https://docs.google.com/presentation/d/#{id}/edit" }
  let(:embed_url) { "https://docs.google.com/presentation/d/#{id}/embed" }
  let(:fetcher) do
    StubFetcher.new
               .stub(url, body: fixture("google_slides", "deck.html"))
               .stub(embed_url, body: fixture("google_slides", "embed.html"))
  end

  describe "#scrape" do
    it "builds a PNG export URL per slide page id" do
      deck = adapter.scrape(url)

      expect(deck.slides.map(&:url)).to eq(
        %w[p1 g1a2b3c4d5_0_0 g1a2b3c4d5_0_6].map do |page|
          "https://docs.google.com/presentation/d/#{id}/export/png?id=#{id}&pageid=#{page}"
        end
      )
    end

    it "strips the Google Slides suffix from the title" do
      expect(adapter.scrape(url).title).to eq("Slide viewer deck")
    end

    it "uses the published-deck endpoints for /d/e/ URLs" do
      published_url = "https://docs.google.com/presentation/d/e/#{id}/pub"
      fetcher = StubFetcher.new
                           .stub(published_url, body: fixture("google_slides", "deck.html"))
                           .stub("https://docs.google.com/presentation/d/e/#{id}/embed",
                                 body: fixture("google_slides", "embed.html"))

      deck = described_class.new(fetcher: fetcher).scrape(published_url)

      expect(deck.slides.first.url)
        .to eq("https://docs.google.com/presentation/d/e/#{id}/export/png?pageid=p1")
    end

    it "raises ExtractionError when the deck is not public" do
      fetcher = StubFetcher.new
                           .stub(url, body: "<html></html>")
                           .stub(embed_url, body: "<html><body>Sign in</body></html>")

      expect { described_class.new(fetcher: fetcher).scrape(url) }
        .to raise_error(Slidescraper::ExtractionError, /is the deck public/)
    end

    it "raises ExtractionError when the URL carries no presentation id" do
      expect { adapter.scrape("https://docs.google.com/document/d/abc/edit") }
        .to raise_error(Slidescraper::ExtractionError, /presentation id/)
    end
  end
end
