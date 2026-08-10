# frozen_string_literal: true

RSpec.describe Slidescraper::Adapters::SpeakerDeck do
  subject(:adapter) { described_class.new(fetcher: fetcher) }

  let(:url) { "https://speakerdeck.com/ngram/slide-viewer" }
  let(:player_url) { "https://speakerdeck.com/player/abc123def456" }
  let(:fetcher) do
    StubFetcher.new
               .stub(url, body: fixture("speaker_deck", "deck.html"))
               .stub(player_url, body: fixture("speaker_deck", "player.html"))
               .stub(%r{/oembed\.json}, body: fixture("speaker_deck", "oembed.json"))
  end

  describe ".handles?" do
    it "claims speakerdeck.com URLs" do
      expect(described_class).to be_handles(url)
    end

    it "ignores other hosts" do
      expect(described_class).not_to be_handles("https://example.com/speakerdeck.com/x")
    end
  end

  describe "#scrape" do
    it "returns the pages in order" do
      deck = adapter.scrape(url)

      expect(deck.slides.map(&:url)).to eq(
        (0..3).map { |n| "https://files.speakerdeck.com/presentations/abc123def456/slide_#{n}.jpg" }
      )
      expect(deck.slides.map(&:number)).to eq([1, 2, 3, 4])
    end

    it "prefers oEmbed for title and author" do
      deck = adapter.scrape(url)

      expect(deck.title).to eq("快適なスライド閲覧生活を実現する Web サービスの開発")
      expect(deck.author).to eq("ngram")
      expect(deck.provider).to eq("speaker_deck")
      expect(deck.page_count).to eq(4)
    end

    it "excludes images served from outside the slide CDN" do
      deck = adapter.scrape(url)

      expect(deck.slides.map(&:url)).to all(start_with("https://files.speakerdeck.com/"))
    end

    it "follows the player only when the deck page has no slide images" do
      adapter.scrape(url)

      expect(fetcher).to be_requested(player_url)
    end

    it "still succeeds when the oEmbed endpoint is unavailable" do
      fetcher = StubFetcher.new
                           .stub(url, body: fixture("speaker_deck", "deck.html"))
                           .stub(player_url, body: fixture("speaker_deck", "player.html"))

      deck = described_class.new(fetcher: fetcher).scrape(url)

      expect(deck.page_count).to eq(4)
      expect(deck.title).to eq("快適なスライド閲覧生活を実現する Web サービスの開発")
    end

    it "raises ExtractionError when no images can be found" do
      fetcher = StubFetcher.new.stub(url, body: "<html><body>nothing here</body></html>")

      expect { described_class.new(fetcher: fetcher).scrape(url) }
        .to raise_error(Slidescraper::ExtractionError, /found no slide images/)
    end
  end
end
