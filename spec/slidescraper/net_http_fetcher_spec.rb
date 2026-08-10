# frozen_string_literal: true

RSpec.describe Slidescraper::NetHttpFetcher do
  subject(:fetcher) { described_class.new }

  describe "#get" do
    it "rejects non-HTTP schemes before opening a socket" do
      expect { fetcher.get("file:///etc/passwd") }
        .to raise_error(Slidescraper::FetchError, /only http\(s\) URLs/)
    end

    it "refuses to connect to a loopback address" do
      expect { fetcher.get("http://127.0.0.1/deck") }
        .to raise_error(Slidescraper::FetchError, /private address/)
    end

    it "refuses to connect to a private range address" do
      expect { fetcher.get("http://10.1.2.3/deck") }
        .to raise_error(Slidescraper::FetchError, /private address/)
    end

    it "refuses the link-local metadata address" do
      expect { fetcher.get("http://169.254.169.254/latest/meta-data/") }
        .to raise_error(Slidescraper::FetchError, /private address/)
    end

    it "can be built without the private address guard" do
      permissive = described_class.new(block_private_addresses: false)

      # No socket is opened: the guard is what would have raised, and with it
      # off the failure comes from the connection attempt instead.
      expect { permissive.get("http://127.0.0.1:9/deck") }
        .to raise_error(Slidescraper::FetchError, /could not fetch/)
    end
  end

  describe "the Fetcher contract" do
    it "requires subclasses to implement #get" do
      expect { Slidescraper::Fetcher.new.get("https://example.com") }
        .to raise_error(NotImplementedError)
    end
  end
end
