# frozen_string_literal: true

module Slidescraper
  module Adapters
    # Docswell (https://www.docswell.com/s/<user>/<id>-<slug>).
    #
    # The deck page only renders the first handful of pages; the rest arrive
    # by script. The embed view it links to carries the whole deck, so that is
    # what this adapter reads. Each page appears there twice, full size and as
    # a `?width=160` thumbnail, which dropping the query collapses.
    class Docswell < Base
      EMBED_URL = %r{\Ahttps://(?:www\.)?docswell\.com/slide/[A-Za-z0-9]+/embed}i
      PAGE_IMAGE = %r{\Ahttps://[a-z0-9.-]*docswell\.com/page/[^/]+\.(?:jpe?g|png|webp)}i

      def self.hosts
        %w[docswell.com]
      end

      def scrape(url)
        page = get(url).html

        # The page links the embed both plainly and with a ?mode= variant.
        embed_url = page.urls(EMBED_URL).map { |found| without_query(found) }.first
        fail_extraction("could not find the embed view for #{url}") unless embed_url

        images = slide_images(embed_url)
        fail_extraction("found no slide images for #{url}") if images.empty?

        build_deck(url, page, images)
      end

      private

      # Page filenames are opaque ids, so document order is the only ordering
      # available. The embed view lists the pages in slide order, which the
      # deck's og:image corroborates: it is always the first page.
      def slide_images(embed_url)
        get(embed_url).html.urls(PAGE_IMAGE).map { |url| without_query(url) }.uniq
      end

      # The deck page carries no author metadata at all, so oEmbed is the only
      # place a name comes from here.
      def build_deck(url, page, images)
        metadata = open_graph_metadata(page)
        oembed = fetch_oembed(page)

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
