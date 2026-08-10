# frozen_string_literal: true

RSpec.describe Slidescraper::Web::App do
  def app
    described_class
  end

  let(:deck_url) { "https://speakerdeck.com/ngram/slide-viewer" }
  let(:deck) do
    Slidescraper::Deck.new(
      provider: "speaker_deck",
      source_url: deck_url,
      title: "テスト & デッキ",
      author: "ngram",
      slides: [
        Slidescraper::Slide.new(number: 1, url: "https://files.speakerdeck.com/p/1.jpg"),
        Slidescraper::Slide.new(number: 2, url: "https://files.speakerdeck.com/p/2.jpg")
      ]
    )
  end

  def stub_client(result)
    client = instance_double(Slidescraper::Client)
    if result.is_a?(StandardError)
      allow(client).to receive(:scrape).and_raise(result)
    else
      allow(client).to receive(:scrape).and_return(result)
    end
    allow(Slidescraper::Client).to receive(:new).and_return(client)
    client
  end

  describe "GET /healthz" do
    it "reports ok for container health checks" do
      get "/healthz"

      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)).to include("status" => "ok")
    end
  end

  describe "GET /" do
    it "renders the form with no URL given" do
      get "/"

      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("スライドの URL")
      expect(last_response.body).not_to include("<ul class=\"slides\">")
    end

    it "renders every page of a scraped deck" do
      stub_client(deck)

      get "/", url: deck_url

      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("https://files.speakerdeck.com/p/1.jpg")
      expect(last_response.body).to include("https://files.speakerdeck.com/p/2.jpg")
      expect(last_response.body).to include("2 ページ")
    end

    it "escapes deck metadata into the page" do
      stub_client(deck)

      get "/", url: deck_url

      expect(last_response.body).to include("テスト &amp; デッキ")
      expect(last_response.body).not_to include("テスト & デッキ")
    end

    it "shows a 422 for an unsupported URL" do
      stub_client(Slidescraper::UnsupportedURLError.new("https://example.com/x"))

      get "/", url: "https://example.com/x"

      expect(last_response.status).to eq(422)
      expect(last_response.body).to include("no adapter registered")
    end

    it "shows a 502 when the remote host fails" do
      stub_client(Slidescraper::FetchError.new("could not fetch"))

      get "/", url: deck_url

      expect(last_response.status).to eq(502)
    end
  end

  describe "GET /api/decks" do
    it "returns the deck as JSON" do
      stub_client(deck)

      get "/api/decks", url: deck_url

      expect(last_response.status).to eq(200)
      expect(last_response.headers["content-type"]).to include("application/json")

      body = JSON.parse(last_response.body)
      expect(body["page_count"]).to eq(2)
      expect(body["slides"].map { |s| s["number"] }).to eq([1, 2])
    end

    it "requires a url parameter" do
      get "/api/decks"

      expect(last_response.status).to eq(400)
      expect(JSON.parse(last_response.body)["error"]).to include("url")
    end

    it "maps extraction failures to 422" do
      stub_client(Slidescraper::ExtractionError.new("found no slide images"))

      get "/api/decks", url: deck_url

      expect(last_response.status).to eq(422)
    end

    it "maps fetch failures to 502" do
      stub_client(Slidescraper::FetchError.new("timed out"))

      get "/api/decks", url: deck_url

      expect(last_response.status).to eq(502)
    end
  end

  describe "caching" do
    it "scrapes a given URL only once within the TTL" do
      client = stub_client(deck)

      get "/api/decks", url: deck_url
      get "/api/decks", url: deck_url

      expect(client).to have_received(:scrape).once
    end
  end

  it "returns JSON for unknown routes" do
    get "/nope"

    expect(last_response.status).to eq(404)
    expect(JSON.parse(last_response.body)).to include("error" => "not found")
  end
end
