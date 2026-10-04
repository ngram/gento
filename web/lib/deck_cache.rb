# frozen_string_literal: true

module Gento
  module Web
    # A tiny in-process TTL cache with LRU eviction.
    #
    # Cloudflare Containers sleep when idle, so this only ever holds a warm
    # instance's recent work — the durable caching lives in the Worker. Its job
    # here is to keep a refresh-happy visitor from re-scraping the same deck.
    class DeckCache
      Entry = Struct.new(:value, :expires_at)

      MONOTONIC = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }

      def initialize(ttl: 3600, max_entries: 500, clock: MONOTONIC)
        @ttl = ttl
        @max_entries = max_entries
        @clock = clock
        @entries = {}
        @mutex = Mutex.new
      end

      def fetch(key)
        hit = read(key)
        return hit if hit

        # Computed outside the lock: scraping takes seconds and must not block
        # every other request. A concurrent duplicate is cheaper than that.
        value = yield
        write(key, value)
        value
      end

      def read(key)
        @mutex.synchronize do
          entry = @entries[key]
          next nil unless entry

          if entry.expires_at <= @clock.call
            @entries.delete(key)
            next nil
          end

          # Re-insert to move this key to the tail: Ruby hashes keep insertion
          # order, which gives LRU eviction for free.
          @entries.delete(key)
          @entries[key] = entry
          entry.value
        end
      end

      def write(key, value)
        @mutex.synchronize do
          @entries.delete(key)
          @entries[key] = Entry.new(value, @clock.call + @ttl)
          @entries.shift while @entries.size > @max_entries
          value
        end
      end

      def size
        @mutex.synchronize { @entries.size }
      end

      def clear
        @mutex.synchronize { @entries.clear }
      end
    end
  end
end
