# frozen_string_literal: true

require "uri"

module Slidescraper
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

      # @return [Slidescraper::Deck]
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
          author: html.meta("og:site_name_author", "author", "twitter:creator")
        }
      end

      def build_slides(urls, width: nil, height: nil)
        urls.each_with_index.map do |url, index|
          Slide.new(number: index + 1, url: url, width: width, height: height)
        end
      end

      # Every image URL referenced by an <img>, including lazy-loading data
      # attributes and srcset candidates, restricted to a CDN host pattern.
      #
      # Scanning by host rather than by CSS class is a deliberate trade: class
      # names churn with every redesign, but a site's image CDN hostname is
      # baked into years of published embeds and effectively never moves.
      def image_candidates(html, base_url, host_pattern)
        urls = html.tags("img").flat_map { |attrs| image_urls_from(attrs) }
        urls.filter_map { |url| absolute_url(url, base_url) }
            .grep(host_pattern)
            .uniq
      end

      def image_urls_from(attrs)
        direct = attrs.values_at("src", "data-src", "data-normal", "data-full",
                                 "data-original", "data-lazy")
        direct.compact + srcset_urls(attrs["srcset"] || attrs["data-srcset"])
      end

      # "a.jpg 320w, b.jpg 640w" -> ["a.jpg", "b.jpg"]
      def srcset_urls(srcset)
        return [] if srcset.nil? || srcset.empty?

        srcset.split(",").filter_map { |candidate| candidate.strip.split(/\s+/).first }
      end

      # Orders slide images by the page number embedded in their URL, which is
      # how every one of these CDNs names them. Falls back to the order the
      # images appeared in when no number is present.
      def order_by_page_number(urls)
        numbered = urls.each_with_index.map do |url, index|
          [page_number_in(url) || Float::INFINITY, index, url]
        end
        numbered.sort_by { |number, index, _| [number, index] }.map(&:last)
      end

      def page_number_in(url)
        path = URI.parse(url).path
        match = path.match(/(?:slide[_-]|[-_])(\d+)(?:[-_.]|\z)/i)
        match && Integer(match[1])
      rescue URI::Error
        nil
      end

      def fail_extraction(message)
        raise ExtractionError, "#{provider}: #{message}"
      end
    end
  end
end
