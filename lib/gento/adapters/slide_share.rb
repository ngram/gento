# frozen_string_literal: true

module Gento
  module Adapters
    # SlideShare (https://www.slideshare.net/<user>/<slug>).
    #
    # SlideShare usually serves the deck to an ordinary HTTP client, but it
    # sits behind bot protection that intermittently answers with a small
    # JavaScript interstitial instead — most readily under bursty access.
    #
    # That interstitial has no slides in it, so without recognising it the
    # adapter would report an empty deck and leave the caller guessing. Naming
    # it costs one check and turns a mystery into something actionable: wait,
    # or supply a JavaScript-capable Fetcher.
    class SlideShare < Base
      CHALLENGE = /Client Challenge|_fs-ch-/
      # <slug>-<page>-<width>.jpg on the slide CDN.
      SLIDE_IMAGE = %r{\Ahttps://[a-z0-9.-]*slidesharecdn\.com/\S+-(\d+)-(\d+)\.(?:jpe?g|png|webp)}i

      def self.hosts
        %w[slideshare.net]
      end

      def fetch(url)
        page = get(url).html
        fail_challenge(url) if challenge?(page)

        images = slide_images(page)
        fail_extraction("found no slide images at #{url}") if images.empty?

        build_deck(url, page, images)
      end

      private

      def challenge?(page)
        page.title.to_s.match?(CHALLENGE) || page.source.match?(CHALLENGE)
      end

      def fail_challenge(url)
        fail_extraction(
          "#{url} returned SlideShare's JavaScript bot challenge instead of the deck. " \
          "Fetching from SlideShare needs a JavaScript-capable Gento::Fetcher; " \
          "the default net/http one cannot get past it."
        )
      end

      # Pages are published at several widths, not always the same set for
      # every page, so keep the widest copy of each.
      def slide_images(page)
        page.urls(SLIDE_IMAGE)
            .group_by { |image| Integer(image[SLIDE_IMAGE, 1]) }
            .sort_by(&:first)
            .map { |_, group| group.max_by { |image| Integer(image[SLIDE_IMAGE, 2]) } }
      end

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
