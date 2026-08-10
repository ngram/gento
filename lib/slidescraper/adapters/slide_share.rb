# frozen_string_literal: true

module Slidescraper
  module Adapters
    # SlideShare (https://www.slideshare.net/<user>/<slug>).
    #
    # Slide images live on image.slidesharecdn.com and are named
    # <slug>-<page>-<width>.jpg, so page order is recoverable from the URL even
    # when the markup renders them out of order or lazily.
    class SlideShare < Base
      IMAGE_HOST = %r{\Ahttps?://[^/]*slidesharecdn\.com/}i
      # Trailing "-<page>-<width>" in the CDN filename.
      PAGED_IMAGE = /-(\d+)-(\d+)\.(?:jpg|jpeg|png|webp)/i

      def self.hosts
        %w[slideshare.net]
      end

      def scrape(url)
        page = get(url).html
        images = largest_per_page(image_candidates(page, url, IMAGE_HOST).grep(PAGED_IMAGE))
        fail_extraction("found no slide images at #{url}") if images.empty?

        build_deck(url, page, images)
      end

      private

      def build_deck(url, page, images)
        metadata = open_graph_metadata(page)
        document = json_ld_document(page)

        Deck.new(
          provider: provider,
          source_url: url,
          title: metadata[:title],
          author: author_from(document) || metadata[:author],
          description: metadata[:description],
          published_at: document["datePublished"],
          slides: build_slides(images)
        )
      end

      # The same page is published at several widths. Keep the widest copy of
      # each page, then order by page number.
      def largest_per_page(images)
        images.group_by { |image| image[PAGED_IMAGE, 1].to_i }
              .sort_by(&:first)
              .map { |_, group| group.max_by { |image| image[PAGED_IMAGE, 2].to_i } }
      end

      def json_ld_document(page)
        page.json_ld.find { |node| node["@type"].to_s.match?(/Presentation|Article|CreativeWork/i) } || {}
      end

      def author_from(document)
        author = document["author"]
        author.is_a?(Hash) ? author["name"] : author
      end
    end
  end
end
