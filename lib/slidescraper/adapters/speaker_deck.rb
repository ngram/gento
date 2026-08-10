# frozen_string_literal: true

require "cgi"

module Slidescraper
  module Adapters
    # Speaker Deck (https://speakerdeck.com/<user>/<slug>).
    #
    # Speaker Deck publishes an oEmbed endpoint, so we ask that first for the
    # title/author and for the deck id, and only then look at markup.
    class SpeakerDeck < Base
      OEMBED_ENDPOINT = "https://speakerdeck.com/oembed.json"
      PLAYER_URL = "https://speakerdeck.com/player/%s"
      IMAGE_HOST = %r{\Ahttps?://files\.speakerdeck\.com/}i
      PLAYER_ID = %r{/player/([0-9a-z-]+)}i

      def self.hosts
        %w[speakerdeck.com]
      end

      def scrape(url)
        oembed = fetch_oembed(url)
        page = get(url).html

        images = image_candidates(page, url, IMAGE_HOST)
        images = player_images(page, oembed) if images.empty?
        fail_extraction("found no slide images at #{url}") if images.empty?

        build_deck(url, page, oembed, images)
      end

      private

      def build_deck(url, page, oembed, images)
        metadata = open_graph_metadata(page)

        Deck.new(
          provider: provider,
          source_url: url,
          title: oembed["title"] || metadata[:title],
          author: oembed["author_name"] || metadata[:author],
          description: metadata[:description],
          slides: build_slides(order_by_page_number(images))
        )
      end

      # oEmbed is a nice-to-have: it gives cleaner metadata than OpenGraph, but
      # the scrape must still succeed when the endpoint is unavailable.
      def fetch_oembed(url)
        endpoint = "#{OEMBED_ENDPOINT}?url=#{CGI.escape(url.to_s)}"
        response = get(endpoint, headers: { "accept" => "application/json" })
        response.json
      rescue FetchError, ExtractionError
        {}
      end

      # The deck page renders its slides through an iframe. When the images are
      # not inlined on the page itself, follow that player and read them there.
      def player_images(page, oembed)
        id = deck_id(page, oembed)
        return [] unless id

        player_url = format(PLAYER_URL, id)
        image_candidates(get(player_url).html, player_url, IMAGE_HOST)
      rescue FetchError
        []
      end

      def deck_id(page, oembed)
        sources = [
          oembed["html"],
          page.tags("div").find { |attrs| attrs["data-id"] }&.fetch("data-id", nil),
          page.tags("iframe").map { |attrs| attrs["src"] }.compact.join(" ")
        ].compact

        sources.each do |source|
          match = source.match(PLAYER_ID)
          return match[1] if match
        end

        nil
      end
    end
  end
end
