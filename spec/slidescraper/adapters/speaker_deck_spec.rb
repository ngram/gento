# frozen_string_literal: true

RSpec.describe Slidescraper::Adapters::SpeakerDeck do
  subject(:adapter) { described_class.new(fetcher: fetcher) }

  # Captured from a real 79-page deck. The page also carries cover images for
  # 34 other decks, which is what makes the id filtering worth testing.
  let(:url) { "https://speakerdeck.com/axbom/digital-ethics-as-a-driver-of-design-innovation" }
  let(:deck_id) { "e751d96689af4d41a0cc55c74507f40e" }
  let(:fetcher) do
    StubFetcher.new
               .stub(url, body: fixture("speaker_deck", "deck.html"))
               .stub(%r{/oembed\.json}, body: fixture("speaker_deck", "oembed.json"))
  end

  describe ".handles?" do
    it "claims speakerdeck.com URLs" do
      expect(described_class).to be_handles(url)
    end

    it "ignores a lookalike host" do
      expect(described_class).not_to be_handles("https://evilspeakerdeck.com/a/b")
    end
  end

  describe "#scrape" do
    it "returns every page in order" do
      deck = adapter.scrape(url)

      expect(deck.page_count).to eq(79)
      expect(deck.slides.map(&:number)).to eq((1..79).to_a)
      expect(deck.slides.first.url)
        .to eq("https://files.speakerdeck.com/presentations/#{deck_id}/slide_0.jpg")
      expect(deck.slides.last.url)
        .to eq("https://files.speakerdeck.com/presentations/#{deck_id}/slide_78.jpg")
    end

    it "excludes the recommended decks shown alongside this one" do
      deck = adapter.scrape(url)

      expect(deck.slides.map(&:url)).to all(include(deck_id))
    end

    it "excludes the low-resolution preview images" do
      deck = adapter.scrape(url)

      expect(deck.slides.map(&:url)).to all(satisfy { |url| !url.include?("preview_slide") })
    end

    it "deduplicates pages that also appear with a cache-busting query" do
      deck = adapter.scrape(url)

      expect(deck.slides.map(&:url).uniq.size).to eq(79)
      expect(deck.slides.map(&:url)).to all(satisfy { |url| !url.include?("?") })
    end

    it "prefers oEmbed for title and author" do
      deck = adapter.scrape(url)

      expect(deck.title).to eq("Digital Ethics as a Driver of Design Innovation")
      expect(deck.author).to eq("Per Axbom")
      expect(deck.provider).to eq("speaker_deck")
    end

    it "still scrapes when the oEmbed endpoint is unavailable" do
      fetcher = StubFetcher.new.stub(url, body: fixture("speaker_deck", "deck.html"))

      deck = described_class.new(fetcher: fetcher).scrape(url)

      expect(deck.page_count).to eq(79)
      expect(deck.title).to eq("Digital Ethics as a Driver of Design Innovation")
    end

    it "raises ExtractionError when the page holds no deck" do
      fetcher = StubFetcher.new.stub(url, body: "<html><body>nothing here</body></html>")

      expect { described_class.new(fetcher: fetcher).scrape(url) }
        .to raise_error(Slidescraper::ExtractionError, /presentation id/)
    end
  end
end
