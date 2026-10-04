# frozen_string_literal: true

RSpec.describe Gento::Adapters::SpeakerDeck do
  subject(:adapter) { described_class.new(fetcher: fetcher) }

  # The fixture holds a 6-page deck, alongside cover images for two other
  # decks — which is what makes the id filtering worth testing.
  let(:url) { "https://speakerdeck.com/example/example-deck" }
  let(:deck_id) { "aaaaaaaabbbbccccddddeeeeffff0000" }
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

  describe "#fetch" do
    it "returns every page in order" do
      deck = adapter.fetch(url)

      expect(deck.page_count).to eq(6)
      expect(deck.slides.map(&:number)).to eq((1..6).to_a)
      expect(deck.slides.first.url)
        .to eq("https://files.speakerdeck.com/presentations/#{deck_id}/slide_0.jpg")
      expect(deck.slides.last.url)
        .to eq("https://files.speakerdeck.com/presentations/#{deck_id}/slide_5.jpg")
    end

    it "excludes the recommended decks shown alongside this one" do
      deck = adapter.fetch(url)

      expect(deck.slides.map(&:url)).to all(include(deck_id))
    end

    it "excludes the low-resolution preview images" do
      deck = adapter.fetch(url)

      expect(deck.slides.map(&:url)).to all(exclude_substring("preview_slide"))
    end

    it "deduplicates pages that also appear with a cache-busting query" do
      deck = adapter.fetch(url)

      expect(deck.slides.map(&:url).uniq.size).to eq(6)
      expect(deck.slides.map(&:url)).to all(exclude_substring("?"))
    end

    it "prefers oEmbed for title and author" do
      deck = adapter.fetch(url)

      expect(deck.title).to eq("Example Deck Title")
      expect(deck.author).to eq("Example Author")
      expect(deck.provider).to eq("speaker_deck")
    end

    it "still fetches the deck when the oEmbed endpoint is unavailable" do
      fetcher = StubFetcher.new.stub(url, body: fixture("speaker_deck", "deck.html"))

      deck = described_class.new(fetcher: fetcher).fetch(url)

      expect(deck.page_count).to eq(6)
      expect(deck.title).to eq("Example Deck Title")
    end

    it "raises ExtractionError when the page holds no deck" do
      fetcher = StubFetcher.new.stub(url, body: "<html><body>nothing here</body></html>")

      expect { described_class.new(fetcher: fetcher).fetch(url) }
        .to raise_error(Gento::ExtractionError, /presentation id/)
    end
  end
end
