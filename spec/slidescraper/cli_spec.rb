# frozen_string_literal: true

RSpec.describe Slidescraper::CLI do
  subject(:cli) { described_class.new(stdout: stdout, stderr: stderr) }

  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:url) { "https://speakerdeck.com/example/example-deck" }
  let(:fetcher) do
    StubFetcher.new
               .stub(url, body: fixture("speaker_deck", "deck.html"))
               .stub(%r{/oembed\.json}, body: fixture("speaker_deck", "oembed.json"))
  end

  before { allow(Slidescraper::NetHttpFetcher).to receive(:new).and_return(fetcher) }

  it "prints the deck as JSON" do
    expect(cli.run([url])).to eq(described_class::EXIT_SUCCESS)

    data = JSON.parse(stdout.string)
    expect(data["page_count"]).to eq(6)
    expect(data["provider"]).to eq("speaker_deck")
  end

  it "prints one image URL per line with --format urls" do
    cli.run(["--format", "urls", url])

    expect(stdout.string.lines.size).to eq(6)
    expect(stdout.string.lines.first).to start_with("https://files.speakerdeck.com/")
  end

  it "reports usage when given no URL" do
    expect(cli.run([])).to eq(described_class::EXIT_USAGE)
    expect(stderr.string).to include("Usage: slidescraper")
  end

  it "rejects an unknown option" do
    expect(cli.run(["--nope"])).to eq(described_class::EXIT_USAGE)
    expect(stderr.string).to include("invalid option")
  end

  it "reports a failing URL on stderr and exits non-zero" do
    expect(cli.run(["https://example.com/deck"])).to eq(described_class::EXIT_FAILURE)
    expect(stderr.string).to include("no adapter registered")
  end

  it "keeps going after one URL fails" do
    expect(cli.run(["https://example.com/deck", url])).to eq(described_class::EXIT_FAILURE)
    expect(stdout.string).to include("speaker_deck")
  end
end
