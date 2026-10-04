# frozen_string_literal: true

RSpec.describe Gento::Web::DeckCache do
  subject(:cache) { described_class.new(ttl: 10, max_entries: 3, clock: -> { time[:now] }) }

  # A settable clock, so the TTL can be tested without sleeping.
  let(:time) { { now: 0.0 } }

  it "computes a value once and serves it from the cache" do
    calls = 0
    2.times { cache.fetch("a") { calls += 1 } }

    expect(calls).to eq(1)
  end

  it "recomputes once the TTL has passed" do
    calls = 0
    cache.fetch("a") { calls += 1 }
    time[:now] = 9.0
    cache.fetch("a") { calls += 1 }
    time[:now] = 10.1
    cache.fetch("a") { calls += 1 }

    expect(calls).to eq(2)
  end

  it "evicts the least recently used entry past the limit" do
    %w[a b c].each { |key| cache.fetch(key) { key } }
    cache.fetch("a") { "recomputed" }
    cache.fetch("d") { "d" }

    expect(cache.size).to eq(3)
    expect(cache.read("b")).to be_nil
    expect(cache.read("a")).to eq("a")
    expect(cache.read("d")).to eq("d")
  end

  it "clears every entry" do
    cache.fetch("a") { "a" }
    cache.clear

    expect(cache.size).to eq(0)
  end
end
