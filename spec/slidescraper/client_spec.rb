# frozen_string_literal: true

RSpec.describe Slidescraper::Client do
  let(:url) { "https://speakerdeck.com/example/example-deck" }
  let(:fetcher) do
    StubFetcher.new
               .stub(url, body: fixture("speaker_deck", "deck.html"))
               .stub(%r{/oembed\.json}, body: fixture("speaker_deck", "oembed.json"))
  end

  describe "#scrape" do
    it "dispatches to the adapter that claims the URL" do
      deck = described_class.new(fetcher: fetcher).scrape(url)

      expect(deck.provider).to eq("speaker_deck")
      expect(deck.page_count).to eq(6)
    end

    it "raises UnsupportedURLError for an unknown host" do
      expect { described_class.new(fetcher: fetcher).scrape("https://example.com/deck") }
        .to raise_error(Slidescraper::UnsupportedURLError, /no adapter registered/)
    end

    it "raises UnsupportedURLError for a non-HTTP URL" do
      expect { described_class.new(fetcher: fetcher).scrape("ftp://speakerdeck.com/x") }
        .to raise_error(Slidescraper::UnsupportedURLError)
    end
  end

  describe "#supports?" do
    subject(:client) { described_class.new(fetcher: fetcher) }

    it "answers for each supported provider" do
      expect(client).to be_supports("https://speakerdeck.com/a/b")
      expect(client).to be_supports("https://www.slideshare.net/a/b")
      expect(client).to be_supports("https://www.docswell.com/s/a/b")
      expect(client).to be_supports("https://docs.google.com/presentation/d/abc/edit")
    end

    it "is false for anything else" do
      expect(client).not_to be_supports("https://example.com/")
    end
  end

  describe "Deck#to_h" do
    it "serializes to JSON-ready data" do
      deck = described_class.new(fetcher: fetcher).scrape(url)
      data = JSON.parse(deck.to_json)

      expect(data["page_count"]).to eq(6)
      expect(data["slides"].first).to include("number" => 1)
      expect(data["source_url"]).to eq(url)
    end
  end
end
