# frozen_string_literal: true

RSpec.describe Slidescraper::Html do
  describe "#tags" do
    it "reads attributes with double, single and unquoted values" do
      html = described_class.new(%(<img src="a.jpg" alt='hi there' width=640>))

      expect(html.tags("img")).to eq([{ "src" => "a.jpg", "alt" => "hi there", "width" => "640" }])
    end

    it "decodes entities in attribute values" do
      html = described_class.new(%(<a href="/x?a=1&amp;b=2">))

      expect(html.tags("a").first["href"]).to eq("/x?a=1&b=2")
    end

    it "handles valueless attributes" do
      html = described_class.new(%(<img src="a.jpg" hidden>))

      expect(html.tags("img").first).to eq({ "src" => "a.jpg", "hidden" => "" })
    end

    it "does not match tags whose name merely starts the same" do
      html = described_class.new(%(<image src="a.jpg"><img src="b.jpg">))

      expect(html.tags("img").map { |attrs| attrs["src"] }).to eq(["b.jpg"])
    end

    it "terminates on malformed markup rather than looping" do
      html = described_class.new(%(<img = = = src="a.jpg">))

      expect(html.tags("img").first["src"]).to eq("a.jpg")
    end
  end

  describe "#meta" do
    let(:html) do
      described_class.new(<<~HTML)
        <meta property="og:title" content="Title from OG">
        <meta name="description" content="Description">
        <meta property="og:image" content="">
      HTML
    end

    it "matches on property or name" do
      expect(html.meta("og:title")).to eq("Title from OG")
      expect(html.meta("description")).to eq("Description")
    end

    it "returns the first non-empty match across several keys" do
      expect(html.meta("og:image", "description")).to eq("Description")
    end

    it "returns nil when nothing matches" do
      expect(html.meta("og:video")).to be_nil
    end
  end

  describe "#link" do
    it "matches a single rel token inside a list" do
      html = described_class.new(%(<link rel="alternate stylesheet" href="/x.css">))

      expect(html.link("stylesheet")).to eq("/x.css")
    end
  end

  describe "#title" do
    it "returns the trimmed, entity-decoded title" do
      html = described_class.new("<title>\n  A &amp; B  \n</title>")

      expect(html.title).to eq("A & B")
    end
  end

  describe "#json_ld" do
    it "parses ld+json blocks and flattens @graph" do
      html = described_class.new(<<~HTML)
        <script type="application/ld+json">
        {"@graph":[{"@type":"Person","name":"ngram"}]}
        </script>
        <script type="application/json">{"ignored":true}</script>
      HTML

      expect(html.json_ld.map { |node| node["@type"] }).to include("Person")
    end

    it "ignores blocks that are not valid JSON" do
      html = described_class.new(%(<script type="application/ld+json">not json</script>))

      expect(html.json_ld).to be_empty
    end
  end

  describe "#inline_scripts" do
    it "returns bodies of scripts without a src" do
      html = described_class.new(%(<script src="/a.js"></script><script>var x = 1;</script>))

      expect(html.inline_scripts).to eq(["var x = 1;"])
    end
  end
end
