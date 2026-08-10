# frozen_string_literal: true

RSpec.describe Slidescraper::Charset do
  def binary(text, encoding)
    text.encode(encoding).dup.force_encoding(Encoding::ASCII_8BIT)
  end

  it "decodes a Shift_JIS body declared in the content type" do
    body = binary("<title>スライド</title>", "Shift_JIS")

    result = described_class.normalize(body, content_type: "text/html; charset=Shift_JIS")

    expect(result.encoding).to eq(Encoding::UTF_8)
    expect(result).to include("スライド")
  end

  it "falls back to a meta charset when the header says nothing" do
    body = binary(%(<meta charset="euc-jp"><title>スライド</title>), "EUC-JP")

    expect(described_class.normalize(body)).to include("スライド")
  end

  it "assumes UTF-8 when nothing declares a charset" do
    body = binary("<title>スライド</title>", "UTF-8")

    expect(described_class.normalize(body)).to include("スライド")
  end

  it "replaces invalid bytes instead of raising" do
    body = (+"<title>ok\xFF\xFE</title>").force_encoding(Encoding::ASCII_8BIT)

    result = described_class.normalize(body)

    expect(result).to be_valid_encoding
    expect(result).to include("ok")
  end

  it "falls back to UTF-8 for an unknown charset name" do
    body = binary("<title>slide</title>", "UTF-8")

    result = described_class.normalize(body, content_type: "text/html; charset=x-not-a-charset")

    expect(result).to include("slide")
    expect(result).to be_valid_encoding
  end
end
