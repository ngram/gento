# frozen_string_literal: true

RSpec.describe Slidescraper::Adapters::GoogleSlides do
  subject(:adapter) { described_class.new(fetcher: fetcher) }

  # Captured from a real, publicly shared 11-page presentation.
  let(:id) { "1IvfYbYKyTRT9da16vlsLLqzpsOqxSHf_Y8tY1lmGA_w" }
  let(:url) { "https://docs.google.com/presentation/d/#{id}/edit" }
  let(:htmlpresent_url) { "https://docs.google.com/presentation/d/#{id}/htmlpresent" }
  let(:fetcher) do
    StubFetcher.new.stub(htmlpresent_url, body: fixture("google_slides", "htmlpresent.html"))
  end

  describe "#scrape" do
    it "builds one PNG export URL per page, in order" do
      deck = adapter.scrape(url)

      expect(deck.page_count).to eq(11)
      expect(deck.slides.first.url).to eq(
        "https://docs.google.com/presentation/d/#{id}/export/png?id=#{id}&pageid=g1080cddb5a_2_84"
      )
      expect(deck.slides.last.url).to end_with("pageid=g1080cddb5a_2_165")
    end

    it "counts each page once" do
      deck = adapter.scrape(url)

      expect(deck.slides.map(&:url).uniq.size).to eq(11)
    end

    it "strips the Google Slides suffix from the title" do
      expect(adapter.scrape(url).title).to eq("Google Presentation")
    end

    it "accepts any URL form that names the presentation" do
      %w[edit preview present].each do |suffix|
        deck = adapter.scrape("https://docs.google.com/presentation/d/#{id}/#{suffix}")
        expect(deck.page_count).to eq(11)
      end
    end

    it "uses the published-deck path for /d/e/ URLs" do
      published = "https://docs.google.com/presentation/d/e/#{id}/pub"
      fetcher = StubFetcher.new.stub(
        "https://docs.google.com/presentation/d/e/#{id}/htmlpresent",
        body: fixture("google_slides", "htmlpresent.html")
      )

      deck = described_class.new(fetcher: fetcher).scrape(published)

      expect(deck.slides.first.url).to start_with(
        "https://docs.google.com/presentation/d/e/#{id}/export/png"
      )
    end

    # A different real deck, whose pages are named "out_s01" and friends
    # rather than the "g<hex>_N_N" of the other fixture. Nothing in the id
    # shape can be relied on, so the adapter must not try.
    context "with a deck whose page ids follow another scheme" do
      let(:id) { "1MVF6nWVXKlFVjLMnUoCtjkQ8pJBh4knmBcv5kFJn_eY" }
      let(:fetcher) do
        StubFetcher.new.stub(htmlpresent_url,
                             body: fixture("google_slides", "htmlpresent-outline-ids.html"))
      end

      it "reads every page" do
        deck = adapter.scrape(url)

        expect(deck.page_count).to eq(18)
        expect(deck.slides.first.url).to end_with("pageid=out_s01")
      end

      it "accepts the /mobilepresent URL form" do
        deck = adapter.scrape("https://docs.google.com/presentation/d/#{id}/mobilepresent?slide=id.out_s01")

        expect(deck.page_count).to eq(18)
      end
    end

    it "raises ExtractionError when the deck is not public" do
      fetcher = StubFetcher.new.stub(htmlpresent_url, body: "<html><body>Sign in</body></html>")

      expect { described_class.new(fetcher: fetcher).scrape(url) }
        .to raise_error(Slidescraper::ExtractionError, /shared publicly/)
    end

    it "raises ExtractionError when the URL names no presentation" do
      expect { adapter.scrape("https://docs.google.com/document/d/abc/edit") }
        .to raise_error(Slidescraper::ExtractionError, /presentation id/)
    end
  end
end
