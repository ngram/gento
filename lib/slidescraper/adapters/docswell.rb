# frozen_string_literal: true

module Slidescraper
  module Adapters
    # Docswell (https://www.docswell.com/s/<user>/<id>-<slug>).
    #
    # Docswell is the youngest of the supported sites and its markup has moved
    # more than the others, so this adapter avoids hard-coding a CDN hostname.
    # Instead it takes the host from og:image — which always points at the
    # deck's own cover slide — and collects every image served from there.
    class Docswell < Base
      FALLBACK_IMAGE_HOST = /docswell\.com\z/i
      IMAGE_EXTENSION = /\.(?:jpe?g|png|webp)(?:\?|\z)/i

      def self.hosts
        %w[docswell.com]
      end

      def scrape(url)
        page = get(url).html
        images = slide_images(page, url)
        fail_extraction("found no slide images at #{url}") if images.empty?

        build_deck(url, page, images)
      end

      private

      def build_deck(url, page, images)
        metadata = open_graph_metadata(page)

        Deck.new(
          provider: provider,
          source_url: url,
          title: metadata[:title],
          author: metadata[:author] || page.meta("og:site_name"),
          description: metadata[:description],
          slides: build_slides(images)
        )
      end

      def slide_images(page, url)
        candidates = image_candidates(page, url, image_host_pattern(page)).grep(IMAGE_EXTENSION)
        order_by_page_number(candidates.uniq)
      end

      # Anchor on whatever host serves the cover image, falling back to any
      # docswell.com host when og:image is missing.
      def image_host_pattern(page)
        cover = page.meta("og:image", "twitter:image")
        host = cover && begin
          URI.parse(cover).host
        rescue URI::Error
          nil
        end
        return FALLBACK_IMAGE_HOST unless host

        %r{\Ahttps?://#{Regexp.escape(host)}/}i
      end
    end
  end
end
