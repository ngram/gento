# frozen_string_literal: true

require "sinatra/base"
require "gento"
require "json"

require_relative "lib/deck_cache"

module Gento
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

      # Fetching a deck costs a request to someone else's site, so never do it
      # twice for the same URL in the TTL window. The Worker in front caches
      # too; this protects the origin sites when it misses.
      CACHE = DeckCache.new(
        ttl: Integer(ENV.fetch("GENTO_CACHE_TTL", 3600)),
        max_entries: Integer(ENV.fetch("GENTO_CACHE_ENTRIES", 500))
      )

      helpers do
        # GENTO_USER_AGENT lets a deployment change how it identifies
        # itself without a rebuild. Worth having because bot protection —
        # SlideShare's especially — reacts to the client as much as to the
        # request, and a container is exactly where you cannot edit code to
        # try something else.
        def client
          @client ||= Gento::Client.new(fetcher: fetcher, robots: robots?)
        end

        def fetcher
          options = { user_agent: ENV.fetch("GENTO_USER_AGENT", nil) }.compact
          Gento::NetHttpFetcher.new(**options)
        end

        # robots.txt is obeyed unless the operator of this deployment turns it
        # off, which is their call to make and their responsibility to own.
        def robots?
          !%w[0 false off no].include?(ENV.fetch("GENTO_ROBOTS", "on").downcase)
        end

        def h(text)
          Rack::Utils.escape_html(text.to_s)
        end

        def deck_for(url)
          CACHE.fetch(url) { client.fetch(url) }
        end

        def json_error(status, message)
          halt status, { "content-type" => "application/json" },
               JSON.generate(error: message)
        end
      end

      get "/healthz" do
        content_type :json
        JSON.generate(status: "ok", version: Gento::VERSION)
      end

      get "/" do
        @url = params["url"].to_s.strip
        @providers = Gento.providers

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
        rescue Gento::UnsupportedURLError, Gento::ExtractionError => e
          # The request named something we cannot turn into slides.
          json_error(422, e.message)
        rescue Gento::RobotsDisallowedError => e
          # The host has said not to. Nothing went wrong; we chose not to ask.
          json_error(403, e.message)
        rescue Gento::FetchError => e
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
      rescue Gento::UnsupportedURLError, Gento::ExtractionError => e
        status 422
        @error = e.message
        erb :index
      rescue Gento::RobotsDisallowedError => e
        status 403
        @error = e.message
        erb :index
      rescue Gento::FetchError => e
        status 502
        @error = e.message
        erb :index
      end
    end
  end
end
