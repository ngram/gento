# frozen_string_literal: true

require "json"

module Slidescraper
  # The result of scraping one slide URL: metadata plus the ordered pages.
  class Deck
    attr_reader :provider, :source_url, :title, :author, :description,
                :published_at, :slides

    def initialize(provider:, source_url:, slides:, title: nil, author: nil,
                   description: nil, published_at: nil)
      @provider = provider.to_s
      @source_url = source_url.to_s
      @title = title
      @author = author
      @description = description
      @published_at = published_at
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
  end
end
