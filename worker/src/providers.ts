/**
 * Host suffixes the gem's adapters claim.
 *
 * This duplicates `Slidescraper::Adapters::*.hosts` on purpose: rejecting an
 * unsupported URL at the edge means never waking the container for a request
 * that was always going to be a 422. `test/providers.test.ts` reads the Ruby
 * source and fails if the two lists drift apart.
 */
export const SUPPORTED_HOSTS = [
  "speakerdeck.com",
  "slideshare.net",
  "docswell.com",
  "docs.google.com",
] as const;

/** Hosts the container is allowed to reach. Anything else is blocked. */
export const EGRESS_ALLOWLIST = [
  "speakerdeck.com",
  "*.speakerdeck.com",
  "slideshare.net",
  "*.slideshare.net",
  "docswell.com",
  "*.docswell.com",
  "docs.google.com",
];

export function isSupportedUrl(candidate: string): boolean {
  let url: URL;
  try {
    url = new URL(candidate);
  } catch {
    return false;
  }

  if (url.protocol !== "https:" && url.protocol !== "http:") return false;

  const host = url.hostname.toLowerCase().replace(/^www\./, "");
  return SUPPORTED_HOSTS.some(
    (claimed) => host === claimed || host.endsWith(`.${claimed}`),
  );
}

/**
 * Cache key for a deck lookup.
 *
 * Normalises away the noise that would otherwise fragment the cache: scheme,
 * a `www.` prefix, a trailing slash, and tracking query parameters. Two URLs
 * that name the same deck should only ever cost one scrape.
 */
export function cacheKeyFor(deckUrl: string): string {
  const url = new URL(deckUrl);
  url.protocol = "https:";
  url.hostname = url.hostname.toLowerCase().replace(/^www\./, "");
  url.hash = "";

  for (const key of [...url.searchParams.keys()]) {
    if (key.startsWith("utm_") || key === "fbclid" || key === "gclid") {
      url.searchParams.delete(key);
    }
  }

  if (url.pathname.length > 1 && url.pathname.endsWith("/")) {
    url.pathname = url.pathname.slice(0, -1);
  }

  return `https://slidescraper.invalid/deck?u=${encodeURIComponent(url.toString())}`;
}
