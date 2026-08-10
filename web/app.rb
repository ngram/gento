# frozen_string_literal: true

require "sinatra/base"
require "slidescraper"
require "json"

require_relative "lib/deck_cache"

module Slidescraper
  module Web
    # The demo service: paste a slide URL, get its pages back as a grid.
    #
    # Deliberately thin. All extraction lives in the gem; this only handles
    # HTTP concerns, caching and rendering.
    class App < Sinatra::Base
      configure do
        set :root, __dir__
        set :views, File.join(__dir__, "views")
        set :public_folder, File.join(__dir__, "public")
        set :show_exceptions, false
        set :raise_errors, false
        # Behind the Cloudflare Worker; bind wide so the container is reachable.
        set :bind, "0.0.0.0"
        set :port, Integer(ENV.fetch("PORT", 8080))
      end

      # Scraping a deck costs a request to someone else's site, so never do it
      # twice for the same URL in the TTL window. The Worker in front caches
      # too; this protects the origin sites when it misses.
      CACHE = DeckCache.new(
        ttl: Integer(ENV.fetch("SLIDESCRAPER_CACHE_TTL", 3600)),
        max_entries: Integer(ENV.fetch("SLIDESCRAPER_CACHE_ENTRIES", 500))
      )

      helpers do
        def client
          @client ||= Slidescraper::Client.new
        end

        def h(text)
          Rack::Utils.escape_html(text.to_s)
        end

        def deck_for(url)
          CACHE.fetch(url) { client.scrape(url) }
        end

        def json_error(status, message)
          halt status, { "content-type" => "application/json" },
               JSON.generate(error: message)
        end
      end

      get "/healthz" do
        content_type :json
        JSON.generate(status: "ok", version: Slidescraper::VERSION)
      end

      get "/" do
        @url = params["url"].to_s.strip
        @providers = Slidescraper.providers

        if @url.empty?
          erb :index
        else
          render_deck(@url)
        end
      end

      get "/api/decks" do
        content_type :json
        url = params["url"].to_s.strip
        json_error(400, "missing required parameter: url") if url.empty?

        begin
          JSON.pretty_generate(deck_for(url).to_h)
        rescue Slidescraper::UnsupportedURLError, Slidescraper::ExtractionError => e
          # The request named something we cannot turn into slides.
          json_error(422, e.message)
        rescue Slidescraper::FetchError => e
          # The slide host is the one having a bad day, not us.
          json_error(502, e.message)
        end
      end

      not_found do
        content_type :json
        JSON.generate(error: "not found")
      end

      error do |e|
        content_type :json
        status 500
        JSON.generate(error: "internal error: #{e.class}")
      end

      private

      def render_deck(url)
        @deck = deck_for(url)
        erb :index
      rescue Slidescraper::UnsupportedURLError, Slidescraper::ExtractionError => e
        status 422
        @error = e.message
        erb :index
      rescue Slidescraper::FetchError => e
        status 502
        @error = e.message
        erb :index
      end
    end
  end
end
