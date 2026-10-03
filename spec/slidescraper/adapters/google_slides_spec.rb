# frozen_string_literal: true

RSpec.describe Slidescraper::Adapters::GoogleSlides do
  subject(:adapter) { described_class.new(fetcher: fetcher) }

  # The fixture holds a 4-page, publicly shared presentation.
  let(:id) { "1ExampleExamplePresentationIdAAAA" }
  let(:url) { "https://docs.google.com/presentation/d/#{id}/edit" }
  let(:htmlpresent_url) { "https://docs.google.com/presentation/d/#{id}/htmlpresent" }
  let(:fetcher) do
    StubFetcher.new.stub(htmlpresent_url, body: fixture("google_slides", "htmlpresent.html"))
  end

  describe "#scrape" do
    it "builds one PNG export URL per page, in order" do
      deck = adapter.scrape(url)

      expect(deck.page_count).to eq(4)
      expect(deck.slides.first.url).to eq(
        "https://docs.google.com/presentation/d/#{id}/export/png?id=#{id}&pageid=g1a2b3c4d5_0_0"
      )
      expect(deck.slides.last.url).to end_with("pageid=g1a2b3c4d5_0_18")
    end

    it "counts each page once" do
      deck = adapter.scrape(url)

      expect(deck.slides.map(&:url).uniq.size).to eq(4)
    end

    it "strips the Google Slides suffix from the title" do
      expect(adapter.scrape(url).title).to eq("Example Presentation")
    end

    it "accepts any URL form that names the presentation" do
      %w[edit preview present].each do |suffix|
        deck = adapter.scrape("https://docs.google.com/presentation/d/#{id}/#{suffix}")
        expect(deck.page_count).to eq(4)
      end
    end

    # Pages are named "out_s01" and friends here rather than the "g<hex>_N_N"
    # of the other fixture. Nothing in the id shape can be relied on, so the
    # adapter must not try.
    context "with a deck whose page ids follow another scheme" do
      let(:id) { "1ExampleOutlineIdsPresentationBBB" }
      let(:fetcher) do
        StubFetcher.new.stub(htmlpresent_url,
                             body: fixture("google_slides", "htmlpresent-outline-ids.html"))
      end

      it "reads every page" do
        deck = adapter.scrape(url)

        expect(deck.page_count).to eq(3)
        expect(deck.slides.first.url).to end_with("pageid=out_s01")
      end

      it "accepts the /mobilepresent URL form" do
        deck = adapter.scrape("https://docs.google.com/presentation/d/#{id}/mobilepresent?slide=id.out_s01")

        expect(deck.page_count).to eq(3)
      end
    end

    context "with a deck published to the web" do
      let(:id) { "2PACX-1vExamplePublishedPresentationIdCCCC" }
      let(:url) { "https://docs.google.com/presentation/d/e/#{id}/pub?start=false&slide=id.p" }
      let(:fetcher) do
        StubFetcher.new.stub("https://docs.google.com/presentation/d/e/#{id}/htmlpresent",
                             body: fixture("google_slides", "htmlpresent-published.html"))
      end

      it "reads every page" do
        deck = adapter.scrape(url)

        expect(deck.page_count).to eq(5)
        expect(deck.title).to eq("Example Presentation")
      end

      # /export/png answers 404 for published decks whatever page id it is
      # given, so the signed viewpage URL in the document is the only thing
      # that actually serves their pages.
      it "takes the signed viewpage URLs rather than building export URLs" do
        deck = adapter.scrape(url)

        expect(deck.slides.map(&:url)).to all(include("/viewpage?"))
        expect(deck.slides.map(&:url)).to all(include("hmac="))
        expect(deck.slides.map(&:url)).to all(exclude_substring("/export/png"))
      end

      it "keeps the pages in order" do
        deck = adapter.scrape(url)

        expect(deck.slides.first.url).to include("pageid=p&")
        expect(deck.slides[1].url).to include("pageid=g9f8e7d6c5_0_4&")
      end

      it "counts each page once" do
        deck = adapter.scrape(url)

        expect(deck.slides.map(&:url).uniq.size).to eq(5)
      end

      it "raises ExtractionError when the deck is no longer published" do
        fetcher = StubFetcher.new.stub("https://docs.google.com/presentation/d/e/#{id}/htmlpresent",
                                       body: "<html><body>Not found</body></html>")

        expect { described_class.new(fetcher: fetcher).scrape(url) }
          .to raise_error(Slidescraper::ExtractionError, /still published/)
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
