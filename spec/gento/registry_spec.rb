# frozen_string_literal: true

RSpec.describe Gento::Registry do
  let(:custom_adapter) do
    Class.new(Gento::Adapters::Base) do
      def self.hosts = ["example.com"]
      def self.provider = "custom"
    end
  end

  it "returns the first adapter that claims the URL" do
    registry = described_class.new([Gento::Adapters::SpeakerDeck])

    expect(registry.find("https://speakerdeck.com/a/b")).to eq(Gento::Adapters::SpeakerDeck)
    expect(registry.find("https://example.com/a/b")).to be_nil
  end

  it "gives registered adapters priority over built-ins" do
    registry = described_class.new([Gento::Adapters::SpeakerDeck]).register(custom_adapter)

    expect(registry.find("https://example.com/deck")).to eq(custom_adapter)
  end

  it "does not let callers mutate the adapter list through the reader" do
    registry = described_class.new([Gento::Adapters::SpeakerDeck])

    expect { registry.adapters << custom_adapter }.to raise_error(FrozenError)
    expect(registry.adapters.size).to eq(1)
  end

  it "lists provider names" do
    expect(described_class.default.providers)
      .to contain_exactly("speaker_deck", "slide_share", "docswell", "google_slides")
  end

  it "tolerates a malformed URL" do
    expect(described_class.default.find("not a url at all")).to be_nil
  end
end
