# frozen_string_literal: true

RSpec.describe Gento::Web::App do
  def app
    described_class
  end

  let(:deck_url) { "https://speakerdeck.com/ngram/slide-viewer" }
  let(:deck) do
    Gento::Deck.new(
      provider: "speaker_deck",
      source_url: deck_url,
      title: "テスト & デッキ",
      author: "ngram",
      slides: [
        Gento::Slide.new(number: 1, url: "https://files.speakerdeck.com/p/1.jpg"),
        Gento::Slide.new(number: 2, url: "https://files.speakerdeck.com/p/2.jpg")
      ]
    )
  end

  def stub_client(result)
    client = instance_double(Gento::Client)
    if result.is_a?(StandardError)
      allow(client).to receive(:scrape).and_raise(result)
    else
      allow(client).to receive(:scrape).and_return(result)
    end
    allow(Gento::Client).to receive(:new).and_return(client)
    client
  end

  describe "user agent configuration" do
    around do |example|
      original = ENV.fetch("GENTO_USER_AGENT", nil)
      example.run
    ensure
      original.nil? ? ENV.delete("GENTO_USER_AGENT") : ENV["GENTO_USER_AGENT"] = original
    end

    it "defaults to the gem's own user agent" do
      ENV.delete("GENTO_USER_AGENT")

      expect(app.new!.send(:fetcher).user_agent)
        .to eq(Gento::NetHttpFetcher::DEFAULT_USER_AGENT)
    end

    it "takes GENTO_USER_AGENT when set" do
      ENV["GENTO_USER_AGENT"] = "Mozilla/5.0 (compatible; example)"

      expect(app.new!.send(:fetcher).user_agent).to eq("Mozilla/5.0 (compatible; example)")
    end
  end

  describe "robots.txt configuration" do
    around do |example|
      original = ENV.fetch("GENTO_ROBOTS", nil)
      example.run
    ensure
      original.nil? ? ENV.delete("GENTO_ROBOTS") : ENV["GENTO_ROBOTS"] = original
    end

    it "is on when nothing is configured" do
      ENV.delete("GENTO_ROBOTS")

      expect(app.new!.send(:robots?)).to be(true)
    end

    it "is off when the deployment turns it off" do
      %w[0 false off no OFF].each do |value|
        ENV["GENTO_ROBOTS"] = value

        expect(app.new!.send(:robots?)).to be(false)
      end
    end
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

    it "renders each page as a link to its own image, so it works without JS" do
      stub_client(deck)

      get "/", url: deck_url

      expect(last_response.body).to include(
        %(<a class="slide-link" href="https://files.speakerdeck.com/p/1.jpg")
      )
    end

    it "ships the viewer controls with the deck" do
      stub_client(deck)

      get "/", url: deck_url

      expect(last_response.body).to include(%(<dialog class="lightbox"))
      expect(last_response.body).to include(%(<script src="/viewer.js"))
      expect(last_response.body).to include(%(data-view="grid"))
    end

    # Hidden in the markup and revealed by the script: with JS off there is
    # only one mode, so offering to switch would be a lie.
    it "hides the mode toggle until the script enables it" do
      stub_client(deck)

      get "/", url: deck_url

      expect(last_response.body).to match(/<div class="view-toggle".*hidden/m)
    end

    it "does not render viewer controls when there is no deck" do
      get "/"

      # The lightbox styles live in the layout and are always present; what
      # must be absent is the dialog itself and the script that drives it.
      expect(last_response.body).not_to include("<dialog")
      expect(last_response.body).not_to include("viewer.js")
    end

    it "shows a 422 for an unsupported URL" do
      stub_client(Gento::UnsupportedURLError.new("https://example.com/x"))

      get "/", url: "https://example.com/x"

      expect(last_response.status).to eq(422)
      expect(last_response.body).to include("no adapter registered")
    end

    it "shows a 502 when the remote host fails" do
      stub_client(Gento::FetchError.new("could not fetch"))

      get "/", url: deck_url

      expect(last_response.status).to eq(502)
    end

    it "shows a 403 when robots.txt disallows the deck" do
      stub_client(Gento::RobotsDisallowedError.new("robots.txt disallows /x"))

      get "/", url: deck_url

      expect(last_response.status).to eq(403)
      expect(last_response.body).to include("robots.txt")
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
      stub_client(Gento::ExtractionError.new("found no slide images"))

      get "/api/decks", url: deck_url

      expect(last_response.status).to eq(422)
    end

    it "maps fetch failures to 502" do
      stub_client(Gento::FetchError.new("timed out"))

      get "/api/decks", url: deck_url

      expect(last_response.status).to eq(502)
    end

    # Not a failure: the host said not to, and we did not.
    it "maps a robots.txt refusal to 403" do
      stub_client(Gento::RobotsDisallowedError.new("robots.txt disallows /x"))

      get "/api/decks", url: deck_url

      expect(last_response.status).to eq(403)
      expect(JSON.parse(last_response.body)["error"]).to include("robots.txt")
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

  it "serves the viewer script as JavaScript" do
    get "/viewer.js"

    expect(last_response.status).to eq(200)
    expect(last_response.headers["content-type"]).to include("javascript")
    expect(last_response.body).to include("showModal")
  end

  it "returns JSON for unknown routes" do
    get "/nope"

    expect(last_response.status).to eq(404)
    expect(JSON.parse(last_response.body)).to include("error" => "not found")
  end
end
