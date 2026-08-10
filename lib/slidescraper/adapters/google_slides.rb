# frozen_string_literal: true

module Slidescraper
  module Adapters
    # Google Slides, for decks that are shared publicly or published to the web.
    #
    # Unlike the other three sites, Google does not render slide images into
    # the page. It exposes a per-page PNG export endpoint instead, keyed by the
    # slide's page object id. So the job here is to recover the presentation id
    # and the ordered list of page ids, then build export URLs from them.
    class GoogleSlides < Base
      EMBED_URL = "https://docs.google.com/presentation/d/%s/embed"
      PUBLISHED_EMBED_URL = "https://docs.google.com/presentation/d/e/%s/embed"
      EXPORT_URL = "https://docs.google.com/presentation/d/%s/export/png?id=%s&pageid=%s"
      PUBLISHED_EXPORT_URL = "https://docs.google.com/presentation/d/e/%s/export/png?pageid=%s"

      # /presentation/d/<id>/... and the published /presentation/d/e/<id>/...
      PRESENTATION_ID = %r{/presentation/d/(e/)?([A-Za-z0-9_-]{16,})}
      # Page object ids as they appear in the viewer payload: "p", "p1",
      # "g1a2b3c4d5_0_6", "SLIDES_API..." and friends.
      PAGE_ID = /"(?:id|objectId)"\s*:\s*"([A-Za-z0-9_]{1,64})"/

      def self.hosts
        %w[docs.google.com]
      end

      def scrape(url)
        published, id = presentation_id(url)
        fail_extraction("could not find a presentation id in #{url}") unless id

        viewer_url = format(published ? PUBLISHED_EMBED_URL : EMBED_URL, id)
        page_ids = page_ids(get(viewer_url).body)
        fail_extraction("could not find slide page ids for #{url}; is the deck public?") if page_ids.empty?

        Deck.new(
          provider: provider,
          source_url: url,
          title: title_for(url),
          slides: build_slides(page_ids.map { |page_id| export_url(published, id, page_id) })
        )
      end

      private

      def presentation_id(url)
        match = url.to_s.match(PRESENTATION_ID)
        return [false, nil] unless match

        [!match[1].nil?, match[2]]
      end

      def export_url(published, id, page_id)
        if published
          format(PUBLISHED_EXPORT_URL, id, page_id)
        else
          format(EXPORT_URL, id, id, page_id)
        end
      end

      # The viewer ships its slide list as a JSON blob inside the page. Keep
      # first occurrences only: ids repeat once per referenced element, and the
      # first mention of each is in slide order.
      def page_ids(body)
        body.scan(PAGE_ID).flatten.uniq
      end

      def title_for(url)
        get(url).html.title&.sub(/\s*-\s*Google (?:Slides|スライド)\s*\z/, "")
      rescue FetchError
        nil
      end
    end
  end
end
