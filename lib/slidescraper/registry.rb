# frozen_string_literal: true

module Slidescraper
  # Maps a URL to the adapter that claims it.
  #
  # Adding support for a new slide host is one class plus one `register` call;
  # nothing else in the library needs to know the site exists.
  class Registry
    class << self
      def default
        @default ||= new(
          [
            Adapters::SpeakerDeck,
            Adapters::SlideShare,
            Adapters::Docswell,
            Adapters::GoogleSlides
          ]
        )
      end

      attr_writer :default
    end

    def initialize(adapters = [])
      @adapters = adapters.dup
    end

    def adapters
      @adapters.dup.freeze
    end

    def register(adapter)
      @adapters.unshift(adapter)
      self
    end

    def find(url)
      @adapters.find { |adapter| adapter.handles?(url) }
    end

    def supports?(url)
      !find(url).nil?
    end

    def providers
      @adapters.map(&:provider)
    end
  end
end
