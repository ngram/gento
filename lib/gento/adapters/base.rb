# frozen_string_literal: true

require "uri"

module Gento
  module Adapters
    # Shared behaviour for the per-site adapters.
    #
    # An adapter answers two questions: "is this URL mine?" and "what are the
    # pages of this deck?". Everything else — HTTP, value objects, JSON output
    # — is the framework's job.
    class Base
      class << self
        # Host suffixes this adapter claims, e.g. %w[speakerdeck.com].
        def hosts
          raise NotImplementedError, "#{self} must declare .hosts"
        end

        def provider
          name.split("::").last
              .gsub(/([a-z\d])([A-Z])/, '\1_\2')
              .downcase
        end

        def handles?(url)
          uri = coerce_uri(url)
          return false unless uri&.host

          host = uri.host.downcase.sub(/\Awww\./, "")
          hosts.any? { |claimed| host == claimed || host.end_with?(".#{claimed}") }
        end

        def coerce_uri(url)
          uri = url.is_a?(URI) ? url : URI.parse(url.to_s)
          uri.is_a?(URI::HTTP) ? uri : nil
        rescue URI::InvalidURIError
          nil
        end
      end

      attr_reader :fetcher

      def initialize(fetcher:)
        @fetcher = fetcher
      end

      # @return [Gento::Deck]
      def scrape(url)
        raise NotImplementedError, "#{self.class} must implement #scrape"
      end

      private

      def provider
        self.class.provider
      end

      def get(url, headers: {})
        fetcher.get(url, headers: headers)
      end

      def absolute_url(candidate, base)
        return nil if candidate.nil? || candidate.to_s.empty?

        URI.join(base.to_s, candidate.to_s).to_s
      rescue URI::Error
        nil
      end

      # Title/author/description as advertised by OpenGraph, which every one of
      # these sites emits and keeps stable for the sake of link previews.
      def open_graph_metadata(html)
        {
          title: html.meta("og:title", "twitter:title") || html.title,
          description: html.meta("og:description", "description"),
          author: html.meta("og:author", "author", "article:author")
        }
      end

      # The oEmbed endpoint a page advertises in its head, if any.
      #
      # Every site here publishes one, so discovering it beats hardcoding a
      # URL per adapter: the site tells us where its own endpoint lives.
      def oembed_endpoint(html)
        html.tags("link")
            .find { |attrs| attrs["type"].to_s.include?("json+oembed") }
            &.fetch("href", nil)
      end

      # oEmbed metadata, or an empty hash.
      #
      # It is always a nice-to-have: cleaner titles and real author names than
      # OpenGraph offers, but never something a scrape should fail over.
      def fetch_oembed(html)
        endpoint = oembed_endpoint(html)
        return {} unless endpoint

        get(endpoint, headers: { "accept" => "application/json" }).json
      rescue FetchError, ExtractionError
        {}
      end

      def build_slides(urls, width: nil, height: nil)
        urls.each_with_index.map do |url, index|
          Slide.new(number: index + 1, url: url, width: width, height: height)
        end
      end

      # The same image is often referenced at several sizes through a query
      # string (`?width=160`, a cache-busting timestamp). Dropping the query
      # before deduplicating collapses those into one page.
      def without_query(url)
        url.to_s.split("?").first.to_s
      end

      def fail_extraction(message)
        raise ExtractionError, "#{provider}: #{message}"
      end
    end
  end
end
