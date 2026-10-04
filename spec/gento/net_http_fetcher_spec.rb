# frozen_string_literal: true

RSpec.describe Gento::NetHttpFetcher do
  subject(:fetcher) { described_class.new }

  def with_env(values)
    original = ENV.to_h.slice(*values.keys)
    values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    values.each_key { |key| ENV.delete(key) }
    original.each { |key, value| ENV[key] = value }
  end

  describe "#get" do
    it "rejects non-HTTP schemes before opening a socket" do
      expect { fetcher.get("file:///etc/passwd") }
        .to raise_error(Gento::FetchError, /only http\(s\) URLs/)
    end

    it "refuses to connect to a loopback address" do
      expect { fetcher.get("http://127.0.0.1/deck") }
        .to raise_error(Gento::FetchError, /private address/)
    end

    it "refuses to connect to a private range address" do
      expect { fetcher.get("http://10.1.2.3/deck") }
        .to raise_error(Gento::FetchError, /private address/)
    end

    it "refuses the link-local metadata address" do
      expect { fetcher.get("http://169.254.169.254/latest/meta-data/") }
        .to raise_error(Gento::FetchError, /private address/)
    end

    it "can be built without the private address guard" do
      permissive = with_env("HTTPS_PROXY" => nil, "https_proxy" => nil) do
        described_class.new(block_private_addresses: false)
      end

      # The guard is what would have raised; with it off the failure comes
      # from the refused connection instead.
      expect { permissive.get("http://127.0.0.1:9/deck") }
        .to raise_error(Gento::FetchError, /could not fetch/)
    end
  end

  describe "proxy configuration" do
    it "reads HTTPS_PROXY, which net/http itself ignores" do
      fetcher = with_env("HTTPS_PROXY" => "http://proxy.test:8080") { described_class.new }

      expect(fetcher.proxy.hostname).to eq("proxy.test")
      expect(fetcher.proxy.port).to eq(8080)
    end

    it "falls back to the lowercase spelling" do
      fetcher = with_env("HTTPS_PROXY" => nil, "https_proxy" => "http://lower.test:3128") do
        described_class.new
      end

      expect(fetcher.proxy.hostname).to eq("lower.test")
    end

    it "takes an explicit proxy over the environment" do
      fetcher = with_env("HTTPS_PROXY" => "http://ignored.test:8080") do
        described_class.new(proxy: "http://explicit.test:9999")
      end

      expect(fetcher.proxy.hostname).to eq("explicit.test")
    end

    it "can be turned off entirely" do
      fetcher = with_env("HTTPS_PROXY" => "http://proxy.test:8080") do
        described_class.new(proxy: nil)
      end

      expect(fetcher.proxy).to be_nil
    end

    it "ignores an unparseable proxy rather than failing every request" do
      fetcher = with_env("HTTPS_PROXY" => "not a proxy") { described_class.new }

      expect(fetcher.proxy).to be_nil
    end

    # Otherwise a request to a service on this machine is answered by the
    # proxy instead of the service.
    it "does not send loopback traffic through the proxy" do
      fetcher = with_env("HTTPS_PROXY" => "http://proxy.test:8080") do
        described_class.new(block_private_addresses: false)
      end

      expect { fetcher.get("http://127.0.0.1:9/deck") }
        .to raise_error(Gento::FetchError, /could not fetch/)
    end
  end

  describe "the Fetcher contract" do
    it "requires subclasses to implement #get" do
      expect { Gento::Fetcher.new.get("https://example.com") }
        .to raise_error(NotImplementedError)
    end
  end
end
