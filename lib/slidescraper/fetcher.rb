# frozen_string_literal: true

require "net/http"
require "uri"
require "resolv"
require "ipaddr"

module Slidescraper
  # The HTTP seam.
  #
  # Everything the library does over the network goes through one of these, so
  # a host that has its own HTTP stack (a Worker's `fetch`, a Faraday
  # connection, a test double) can supply an adapter instead of dragging
  # net/http along.
  #
  # Implementations must return a Slidescraper::Response and raise
  # Slidescraper::FetchError on transport failure.
  class Fetcher
    def get(url, headers: {})
      raise NotImplementedError, "#{self.class} must implement #get"
    end
  end

  # Default fetcher, built on net/http from the standard library.
  class NetHttpFetcher < Fetcher
    DEFAULT_USER_AGENT =
      "slidescraper/#{VERSION} (+https://github.com/ngram/slidescraper)".freeze

    # Ranges that a public slide host has no business resolving to. Checked
    # before connecting so a redirect cannot walk us into the private network.
    BLOCKED_RANGES = [
      IPAddr.new("0.0.0.0/8"), IPAddr.new("10.0.0.0/8"),
      IPAddr.new("127.0.0.0/8"), IPAddr.new("169.254.0.0/16"),
      IPAddr.new("172.16.0.0/12"), IPAddr.new("192.168.0.0/16"),
      IPAddr.new("100.64.0.0/10"), IPAddr.new("::1/128"),
      IPAddr.new("fc00::/7"), IPAddr.new("fe80::/10")
    ].freeze

    attr_reader :user_agent, :open_timeout, :read_timeout, :max_redirects, :proxy

    def initialize(user_agent: DEFAULT_USER_AGENT, open_timeout: 5, read_timeout: 10,
                   max_redirects: 5, block_private_addresses: true, proxy: :env)
      @user_agent = user_agent
      @open_timeout = open_timeout
      @read_timeout = read_timeout
      @max_redirects = max_redirects
      @block_private_addresses = block_private_addresses
      @proxy = proxy == :env ? proxy_from_env : normalize_proxy(proxy)
      super()
    end

    def get(url, headers: {})
      uri = normalize_uri(url)
      redirects = 0

      loop do
        response = request(uri, headers)
        location = response["location"]

        return build_response(response, uri) unless redirect?(response) && location

        redirects += 1
        if redirects > max_redirects
          raise TooManyRedirectsError.new("more than #{max_redirects} redirects", url: url)
        end

        uri = normalize_uri(URI.join(uri, location))
      end
    end

    private

    def request(uri, headers)
      addresses = resolve(uri.hostname)
      guard_address!(uri, addresses)

      connection(uri, addresses).start do |http|
        http.request(Net::HTTP::Get.new(uri, request_headers(headers)))
      end
    rescue Timeout::Error, SystemCallError, IOError, OpenSSL::SSL::SSLError,
           Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError => e
      raise FetchError.new("could not fetch #{uri}: #{e.class}: #{e.message}", url: uri.to_s)
    end

    # Built explicitly rather than through Net::HTTP.start's keyword form:
    # there the proxy arguments are positional, so passing them as keywords
    # puts them in the options hash where they are silently ignored, leaving
    # every request unproxied. Passing nil for the address disables proxying.
    def connection(uri, addresses)
      http = Net::HTTP.new(uri.hostname, uri.port, *proxy_parts(addresses))
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = open_timeout
      http.read_timeout = read_timeout
      http
    end

    # net/http only consults the lowercase `http_proxy`, and never for HTTPS,
    # so environments that set HTTPS_PROXY — most corporate networks and every
    # sandboxed CI runner — go unproxied and fail. Read both spellings.
    def proxy_from_env
      value = ENV["HTTPS_PROXY"] || ENV["https_proxy"] || ENV["HTTP_PROXY"] || ENV.fetch("http_proxy", nil)
      normalize_proxy(value)
    end

    def normalize_proxy(value)
      return nil if value.nil? || value.to_s.empty?

      uri = value.is_a?(URI) ? value : URI.parse(value.to_s)
      uri.host ? uri : nil
    rescue URI::InvalidURIError
      nil
    end

    # Identity encoding: we decode charsets ourselves and have no reason to
    # also own gzip handling.
    def request_headers(headers)
      { "user-agent" => user_agent, "accept-encoding" => "identity" }
        .merge(headers.transform_keys { |key| key.to_s.downcase })
    end

    def build_response(response, uri)
      status = response.code.to_i
      unless status.between?(200, 299)
        raise ResponseError.new("#{uri} responded #{status}", url: uri.to_s, status: status)
      end

      headers = response.each_header.to_h
      Response.new(status: status, body: response.body.to_s, url: uri.to_s, headers: headers)
    end

    def redirect?(response)
      response.is_a?(Net::HTTPRedirection)
    end

    def normalize_uri(url)
      uri = url.is_a?(URI) ? url : URI.parse(url.to_s)
      unless uri.is_a?(URI::HTTP)
        raise FetchError.new("only http(s) URLs are supported, got #{url.inspect}", url: url.to_s)
      end

      uri
    end

    # Best-effort SSRF guard. There is an unavoidable gap between resolving a
    # name here and net/http resolving it again when it connects; closing it
    # properly needs socket-level pinning. This still stops the ordinary case
    # of a redirect pointed at an internal address.
    def guard_address!(uri, addresses)
      return unless @block_private_addresses

      blocked = blocked_address(addresses)
      return unless blocked

      raise FetchError.new("refusing to connect to private address #{blocked} (#{uri.hostname})",
                           url: uri.to_s)
    end

    # A proxy exists to reach the outside world, and loopback or private
    # addresses are not out there. Routing them through one is how a request
    # to a service on this machine ends up answered by the proxy instead.
    def proxy_parts(addresses)
      return [nil, nil, nil, nil] if proxy.nil? || blocked_address(addresses)

      [proxy.hostname, proxy.port, proxy.user, proxy.password]
    end

    def blocked_address(addresses)
      addresses.find { |address| BLOCKED_RANGES.any? { |range| range.include?(address) } }
    end

    def resolve(host)
      return [IPAddr.new(host)] if ip_literal?(host)

      Resolv.getaddresses(host).filter_map do |address|
        IPAddr.new(address)
      rescue IPAddr::Error
        nil
      end
    end

    def ip_literal?(host)
      IPAddr.new(host)
      true
    rescue IPAddr::Error
      false
    end
  end
end
