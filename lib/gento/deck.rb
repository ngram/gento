# frozen_string_literal: true

require "json"

module Gento
  # The result of fetching one slide URL: metadata plus the ordered pages.
  class Deck
    attr_reader :provider, :source_url, :title, :author, :description,
                :published_at, :slides

    def initialize(provider:, source_url:, slides:, title: nil, author: nil,
                   description: nil, published_at: nil)
      @provider = provider.to_s
      @source_url = source_url.to_s
      @title = normalize(title)
      @author = normalize(author)
      @description = normalize(description)
      @published_at = normalize(published_at)
      @slides = slides.sort_by(&:number).freeze
      freeze
    end

    def page_count
      slides.size
    end

    def to_h
      {
        provider: provider,
        source_url: source_url,
        title: title,
        author: author,
        description: description,
        published_at: published_at,
        page_count: page_count,
        slides: slides.map(&:to_h)
      }.compact
    end

    def to_json(*args)
      to_h.to_json(*args)
    end

    private

    # Slide titles are typed into a design tool, so they arrive carrying the
    # author's own line breaks — vertical tabs, in Docswell's case. Collapsing
    # them here means every adapter gets it right without remembering to.
    def normalize(text)
      return nil if text.nil?

      collapsed = text.to_s.gsub(/[[:space:][:cntrl:]]+/, " ").strip
      collapsed.empty? ? nil : collapsed
    end
  end
end
