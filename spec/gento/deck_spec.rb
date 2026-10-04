# frozen_string_literal: true

RSpec.describe Gento::Deck do
  def slide(number, url = "https://cdn.example.com/#{number}.jpg")
    Gento::Slide.new(number: number, url: url)
  end

  def deck(slides)
    described_class.new(provider: "test", source_url: "https://example.com/d", slides: slides)
  end

  it "orders slides by page number regardless of input order" do
    result = deck([slide(3), slide(1), slide(2)])

    expect(result.slides.map(&:number)).to eq([1, 2, 3])
    expect(result.page_count).to eq(3)
  end

  it "omits absent metadata from the hash form" do
    expect(deck([slide(1)]).to_h.keys)
      .to contain_exactly(:provider, :source_url, :page_count, :slides)
  end

  it "is immutable" do
    result = deck([slide(1)])

    expect(result).to be_frozen
    expect { result.slides << slide(2) }.to raise_error(FrozenError)
  end

  it "collapses the line breaks authors type into slide titles" do
    result = described_class.new(
      provider: "test", source_url: "https://example.com/d", slides: [slide(1)],
      title: "AI\u000Bと\u000B\u000Bひとりで  働く\n"
    )

    expect(result.title).to eq("AI と ひとりで 働く")
  end

  it "treats whitespace-only metadata as absent" do
    result = described_class.new(
      provider: "test", source_url: "https://example.com/d", slides: [slide(1)], author: "  \n "
    )

    expect(result.author).to be_nil
    expect(result.to_h).not_to have_key(:author)
  end

  it "round-trips through JSON" do
    data = JSON.parse(deck([slide(1), slide(2)]).to_json)

    expect(data["page_count"]).to eq(2)
    expect(data["slides"].map { |s| s["number"] }).to eq([1, 2])
  end
end
