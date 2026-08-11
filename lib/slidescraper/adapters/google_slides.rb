# frozen_string_literal: true

module Slidescraper
  module Adapters
    # Google Slides, for decks shared publicly or published to the web.
    #
    # Google does not render page images into the deck page; it exposes a
    # per-page PNG export keyed by the slide's page object id. Recovering an
    # ordered list of those ids is the whole job.
    #
    # The viewer at /embed is the obvious place to look and the wrong one: its
    # payload mixes page ids with the ids of elements drawn on those pages,
    # with nothing in the id itself to tell them apart. /htmlpresent instead
    # references each page exactly once, in order, so that is what we read.
    class GoogleSlides < Base
      HTMLPRESENT_URL = "https://docs.google.com/presentation/d/%s%s/htmlpresent"
      EXPORT_URL = "https://docs.google.com/presentation/d/%s%s/export/png?id=%s&pageid=%s"

      # /presentation/d/<id>/... and the published /presentation/d/e/<id>/...
      PRESENTATION_ID = %r{/presentation/d/(e/)?([A-Za-z0-9_-]{16,})}
      PAGE_ID = /[?&]pageid=([A-Za-z0-9_]+)/

      def self.hosts
        %w[docs.google.com]
      end

      def scrape(url)
        prefix, id = presentation_id(url)
        fail_extraction("could not find a presentation id in #{url}") unless id

        page = get(format(HTMLPRESENT_URL, prefix, id)).html
        pages = page_ids(page, url)

        Deck.new(
          provider: provider,
          source_url: url,
          title: title_from(page),
          slides: build_slides(pages.map { |page_id| format(EXPORT_URL, prefix, id, id, page_id) })
        )
      end

      private

      # Each page is referenced exactly once here, in order.
      def page_ids(page, url)
        ids = page.source.scan(PAGE_ID).flatten.uniq
        fail_extraction("found no slide pages for #{url}; is the deck shared publicly?") if ids.empty?

        ids
      end

      def presentation_id(url)
        match = url.to_s.match(PRESENTATION_ID)
        return [nil, nil] unless match

        [match[1].to_s, match[2]]
      end

      def title_from(page)
        page.title&.sub(/\s*-\s*Google (?:Slides|スライド)\s*\z/, "")
      end
    end
  end
end
