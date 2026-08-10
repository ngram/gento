import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

import { describe, expect, it } from "vitest";

import { SUPPORTED_HOSTS, cacheKeyFor, isSupportedUrl } from "../src/providers";

describe("isSupportedUrl", () => {
  it.each([
    "https://speakerdeck.com/ngram/slide-viewer",
    "https://www.slideshare.net/ngram/slide-viewer",
    "https://de.slideshare.net/ngram/slide-viewer",
    "https://www.docswell.com/s/ngram/ZX9K2P-deck",
    "https://docs.google.com/presentation/d/abc/edit",
  ])("accepts %s", (url) => {
    expect(isSupportedUrl(url)).toBe(true);
  });

  it.each([
    "https://example.com/deck",
    // A supported host appearing in the path must not count.
    "https://example.com/speakerdeck.com/deck",
    // Nor as a suffix of an attacker-controlled domain.
    "https://evilspeakerdeck.com/deck",
    "ftp://speakerdeck.com/deck",
    "not a url",
    "",
  ])("rejects %s", (url) => {
    expect(isSupportedUrl(url)).toBe(false);
  });
});

describe("cacheKeyFor", () => {
  it("collapses URLs that name the same deck", () => {
    const variants = [
      "https://speakerdeck.com/ngram/talk",
      "http://speakerdeck.com/ngram/talk",
      "https://www.speakerdeck.com/ngram/talk",
      "https://speakerdeck.com/ngram/talk/",
      "https://speakerdeck.com/ngram/talk#slide-3",
      "https://speakerdeck.com/ngram/talk?utm_source=twitter",
    ];

    const keys = new Set(variants.map(cacheKeyFor));

    expect(keys.size).toBe(1);
  });

  it("keeps meaningful query parameters", () => {
    expect(cacheKeyFor("https://docs.google.com/presentation/d/a/pub?start=false")).not.toEqual(
      cacheKeyFor("https://docs.google.com/presentation/d/a/pub"),
    );
  });

  it("distinguishes different decks", () => {
    expect(cacheKeyFor("https://speakerdeck.com/a/one")).not.toEqual(
      cacheKeyFor("https://speakerdeck.com/a/two"),
    );
  });
});

describe("host list", () => {
  /**
   * The Worker rejects unsupported URLs at the edge, which is only correct
   * while its host list matches the gem's. Read the adapters and compare, so
   * adding a site to the gem without updating the Worker fails here rather
   * than silently 422-ing a supported deck.
   */
  it("matches the hosts the gem's adapters claim", () => {
    const adapterDir = join(import.meta.dirname, "..", "..", "lib", "slidescraper", "adapters");
    const hosts = readdirSync(adapterDir)
      .filter((file) => file.endsWith(".rb") && file !== "base.rb")
      .flatMap((file) => {
        const source = readFileSync(join(adapterDir, file), "utf8");
        const declaration = source.match(/def self\.hosts\s+%w\[([^\]]+)\]/);
        if (!declaration?.[1]) throw new Error(`no .hosts found in ${file}`);
        return declaration[1].trim().split(/\s+/);
      });

    expect([...hosts].sort()).toEqual([...SUPPORTED_HOSTS].sort());
  });
});
