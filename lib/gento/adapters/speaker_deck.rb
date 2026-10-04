# frozen_string_literal: true

module Gento
  module Adapters
    # Speaker Deck (https://speakerdeck.com/<user>/<slug>).
    #
    # The deck page carries every page image at full size, in <a href>
    # elements. It also carries cover images for roughly thirty recommended
    # decks, so matching on the CDN hostname alone would silently splice other
    # people's slides into the result. Keying on this deck's own presentation
    # id is what keeps them out.
    class SpeakerDeck < Base
      PLAYER_ID = %r{/player/([0-9a-f-]+)}i
      DECK_ID = /\A[0-9a-f-]{8,}\z/i

      def self.hosts
        %w[speakerdeck.com]
      end

      def scrape(url)
        page = get(url).html
        oembed = fetch_oembed(page)

        id = deck_id(page, oembed)
        fail_extraction("could not find the presentation id for #{url}") unless id

        images = slide_images(page, id)
        fail_extraction("found no slide images at #{url}") if images.empty?

        build_deck(url, page, oembed, images)
      end

      private

      # Full-size pages only: the same presentation also publishes
      # `preview_slide_N.jpg` thumbnails, which this pattern excludes.
      def slide_images(page, id)
        pattern = %r{
          \Ahttps://files\.speakerdeck\.com/presentations/
          #{Regexp.escape(id)}/slide_(\d+)\.[a-z]+
        }xi

        page.urls(pattern)
            .map { |url| without_query(url) }
            .uniq
            .sort_by { |url| Integer(url[pattern, 1]) }
      end

      # oEmbed names the id inside a player URL; the page itself carries it
      # bare, as the data-id of the embed placeholder.
      def deck_id(page, oembed)
        player_id(oembed["html"]) || embed_data_id(page) || player_id(page.source)
      end

      def player_id(text)
        text.to_s[PLAYER_ID, 1]
      end

      def embed_data_id(page)
        page.tags("div")
            .filter_map { |attrs| attrs["data-id"] }
            .find { |id| id.match?(DECK_ID) }
      end

      def build_deck(url, page, oembed, images)
        metadata = open_graph_metadata(page)

        Deck.new(
          provider: provider,
          source_url: url,
          title: oembed["title"] || metadata[:title],
          author: oembed["author_name"] || metadata[:author],
          description: metadata[:description],
          slides: build_slides(images)
        )
      end
    end
  end
end
