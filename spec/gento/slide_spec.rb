# frozen_string_literal: true

RSpec.describe Gento::Slide do
  let(:url) { "https://cdn.example.com/1.jpg" }

  it "compares by value, not identity" do
    original = described_class.new(number: 1, url: url)
    rebuilt = described_class.new(number: 1, url: url.dup)

    expect(original).to eq(rebuilt)
    expect(original).not_to equal(rebuilt)
  end

  it "distinguishes slides that differ" do
    expect(described_class.new(number: 1, url: url))
      .not_to eq(described_class.new(number: 2, url: url))
  end

  it "can be used as a hash key" do
    set = [described_class.new(number: 1, url: url), described_class.new(number: 1, url: url)].uniq

    expect(set.size).to eq(1)
  end

  it "coerces the page number" do
    expect(described_class.new(number: "2", url: url).number).to eq(2)
  end

  it "omits absent dimensions from the hash form" do
    expect(described_class.new(number: 1, url: url).to_h.keys).to contain_exactly(:number, :url)
  end

  it "keeps dimensions when given" do
    slide = described_class.new(number: 1, url: url, width: 1600, height: 900)

    expect(slide.to_h).to include(width: 1600, height: 900)
  end
end
