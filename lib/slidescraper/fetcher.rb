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

    attr_reader :user_agent, :open_timeout, :read_timeout, :max_redirects

    def initialize(user_agent: DEFAULT_USER_AGENT, open_timeout: 5,
                   read_timeout: 10, max_redirects: 5, block_private_addresses: true)
      @user_agent = user_agent
      @open_timeout = open_timeout
      @read_timeout = read_timeout
      @max_redirects = max_redirects
      @block_private_addresses = block_private_addresses
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
      guard_address!(uri)

      Net::HTTP.start(uri.hostname, uri.port, **connection_options(uri)) do |http|
        http.request(Net::HTTP::Get.new(uri, request_headers(headers)))
      end
    rescue Timeout::Error, SystemCallError, IOError, OpenSSL::SSL::SSLError,
           Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError => e
      raise FetchError.new("could not fetch #{uri}: #{e.class}: #{e.message}", url: uri.to_s)
    end

    def connection_options(uri)
      {
        use_ssl: uri.scheme == "https",
        open_timeout: open_timeout,
        read_timeout: read_timeout
      }
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
    def guard_address!(uri)
      return unless @block_private_addresses

      addresses = resolve(uri.hostname)
      blocked = addresses.find { |address| BLOCKED_RANGES.any? { |range| range.include?(address) } }
      return unless blocked

      raise FetchError.new("refusing to connect to private address #{blocked} (#{uri.hostname})",
                           url: uri.to_s)
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
