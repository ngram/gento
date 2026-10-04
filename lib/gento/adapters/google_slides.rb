# frozen_string_literal: true

module Gento
  module Adapters
    # Google Slides, for decks shared publicly or published to the web.
    #
    # Google does not render page images into the deck page, so the job here
    # is to find the ordered list of pages and name an image for each.
    #
    # The viewer at /embed is the obvious place to look and the wrong one: its
    # payload mixes page ids with the ids of elements drawn on those pages,
    # with nothing in the id itself to tell them apart. /htmlpresent instead
    # references each page exactly once, in order, so that is what we read.
    class GoogleSlides < Base
      BASE_URL = "https://docs.google.com/presentation/d/%s"

      # /presentation/d/<id>/... and the published /presentation/d/e/<id>/...
      # Published ids contain hyphens, ordinary ones do not.
      PRESENTATION_ID = %r{/presentation/d/(e/)?([A-Za-z0-9_-]{16,})}
      PAGE_ID = /[?&]pageid=([A-Za-z0-9_]+)/
      VIEWPAGE = %r{/viewpage\?}

      def self.hosts
        %w[docs.google.com]
      end

      def scrape(url)
        published, id = presentation_id(url)
        fail_extraction("could not find a presentation id in #{url}") unless id

        page = get("#{deck_base(published, id)}/htmlpresent").html
        images = published ? viewpage_images(page, url) : export_images(page, url, published, id)

        Deck.new(
          provider: provider,
          source_url: url,
          title: title_from(page),
          slides: build_slides(images)
        )
      end

      private

      def deck_base(published, id)
        format(BASE_URL, published ? "e/#{id}" : id)
      end

      # Ordinary decks: build export URLs from the page ids. These are stable,
      # so a caller can keep them, and they redirect to a signed image.
      def export_images(page, url, published, id)
        base = deck_base(published, id)

        page_ids(page, url).map { |page_id| "#{base}/export/png?id=#{id}&pageid=#{page_id}" }
      end

      # Published decks: /export/png answers 404 for them, whatever page id it
      # is given. The only thing that serves their pages is the viewpage URL
      # embedded in the document, which carries its own signature — so take it
      # verbatim rather than trying to construct one.
      #
      # Those signatures expire, so unlike the export URLs these are worth
      # fetching promptly rather than storing.
      def viewpage_images(page, url)
        images = page.urls(VIEWPAGE)
        fail_extraction("found no slide pages for #{url}; is the deck still published?") if images.empty?

        images
      end

      # Each page is referenced exactly once here, in order.
      def page_ids(page, url)
        ids = page.source.scan(PAGE_ID).flatten.uniq
        fail_extraction("found no slide pages for #{url}; is the deck shared publicly?") if ids.empty?

        ids
      end

      def presentation_id(url)
        match = url.to_s.match(PRESENTATION_ID)
        return [false, nil] unless match

        [!match[1].nil?, match[2]]
      end

      def title_from(page)
        page.title&.sub(/\s*-\s*Google (?:Slides|スライド)\s*\z/, "")
      end
    end
  end
end
