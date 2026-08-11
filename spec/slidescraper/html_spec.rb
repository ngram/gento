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

  describe "#tags nesting" do
    # Regression: scanning used to consume element content, so a <div> inside
    # another <div> was invisible — which is most of the divs on a real page.
    it "finds tags nested inside another tag of the same name" do
      html = described_class.new(
        %(<div id="outer"><div id="middle"><div id="inner" data-id="x"></div></div></div>)
      )

      expect(html.tags("div").map { |attrs| attrs["id"] }).to eq(%w[outer middle inner])
      expect(html.tags("div").last["data-id"]).to eq("x")
    end
  end

  describe "#urls" do
    let(:html) do
      described_class.new(<<~HTML)
        <a href="https://cdn.example.com/slide_1.jpg">one</a>
        <img data-lazy="https://cdn.example.com/slide_2.jpg">
        <div style="background: url(https://cdn.example.com/slide_3.jpg?w=10&amp;h=20)"></div>
        <a href="/relative.jpg">skipped</a>
        <a href="https://other.example.net/logo.svg">skipped</a>
      HTML
    end

    it "finds URLs regardless of which element or attribute holds them" do
      expect(html.urls(%r{\Ahttps://cdn\.example\.com/})).to eq(
        [
          "https://cdn.example.com/slide_1.jpg",
          "https://cdn.example.com/slide_2.jpg",
          "https://cdn.example.com/slide_3.jpg?w=10&h=20"
        ]
      )
    end

    it "decodes entities inside the URL" do
      expect(html.urls(/slide_3/).first).to include("w=10&h=20")
    end

    it "stops at the closing parenthesis of a CSS url()" do
      expect(html.urls(/slide_3/).first).not_to include(")")
    end

    it "deduplicates repeated references" do
      repeated = described_class.new(%(<a href="https://x.test/a.jpg"><img src="https://x.test/a.jpg">))

      expect(repeated.urls).to eq(["https://x.test/a.jpg"])
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

    # Real deck descriptions are full of these; CGI.unescapeHTML leaves them.
    it "decodes typographic entities beyond the predefined five" do
      html = described_class.new("<title>Truncated&hellip; and &mdash; dashed</title>")

      expect(html.title).to eq("Truncated… and — dashed")
    end

    it "decodes numeric references" do
      expect(described_class.new("<title>&#65;&#x42;</title>").title).to eq("AB")
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
