# frozen_string_literal: true

module Gento
  # A single page of a deck.
  #
  # `url` always points at the original host. We deliberately never re-host or
  # proxy slide images: this library reports where the images are, and leaves
  # serving them to the site that owns them.
  class Slide
    attr_reader :number, :url, :width, :height, :thumbnail_url

    def initialize(number:, url:, width: nil, height: nil, thumbnail_url: nil)
      @number = Integer(number)
      @url = url.to_s
      @width = width && Integer(width)
      @height = height && Integer(height)
      @thumbnail_url = thumbnail_url&.to_s
      freeze
    end

    def to_h
      {
        number: number,
        url: url,
        width: width,
        height: height,
        thumbnail_url: thumbnail_url
      }.compact
    end

    def ==(other)
      other.is_a?(Slide) && other.to_h == to_h
    end
    alias eql? ==

    def hash
      to_h.hash
    end
  end
end
