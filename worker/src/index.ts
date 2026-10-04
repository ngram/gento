import { getContainer } from "@cloudflare/containers";

import { cacheKeyFor, isSupportedUrl } from "./providers";

export { GentoContainer } from "./container";

/** How long an extracted deck stays in the edge cache. */
const CACHE_TTL_SECONDS = 60 * 60 * 6;

export default {
  async fetch(request, env, ctx): Promise<Response> {
    const url = new URL(request.url);

    if (request.method !== "GET" && request.method !== "HEAD") {
      return json(405, { error: "method not allowed" }, { allow: "GET, HEAD" });
    }

    if (url.pathname === "/healthz") {
      return json(200, { status: "ok", edge: "worker" });
    }

    const deckUrl = url.searchParams.get("url")?.trim();

    // Reject unsupported URLs here rather than paying to wake the container
    // for an answer we already know.
    if (deckUrl && !isSupportedUrl(deckUrl)) {
      return respondUnsupported(url, deckUrl);
    }

    if (!deckUrl) return proxy(request, env);

    return cached(request, env, ctx, deckUrl);
  },
} satisfies ExportedHandler<Env>;

/**
 * Serves a deck from the edge cache, falling back to the container.
 *
 * Scraping costs a round trip to someone else's site, so a cache hit is worth
 * real money and real politeness. Only successful responses are stored.
 */
async function cached(
  request: Request,
  env: Env,
  ctx: ExecutionContext,
  deckUrl: string,
): Promise<Response> {
  const cache = caches.default;
  const key = new Request(cacheKeyFor(deckUrl), { method: "GET" });

  const hit = await cache.match(key);
  if (hit) {
    const response = new Response(hit.body, hit);
    response.headers.set("x-gento-cache", "hit");
    return response;
  }

  const response = await proxy(request, env);
  if (!response.ok) return response;

  // Tee the body: one copy goes to the cache, the other to the client.
  const toCache = response.clone();
  toCache.headers.set("cache-control", `public, max-age=${CACHE_TTL_SECONDS}`);
  ctx.waitUntil(
    cache.put(key, new Response(toCache.body, toCache)).catch((error) => {
      console.error("cache put failed", error);
    }),
  );

  const fresh = new Response(response.body, response);
  fresh.headers.set("x-gento-cache", "miss");
  return fresh;
}

async function proxy(request: Request, env: Env): Promise<Response> {
  try {
    return await getContainer(env.CONTAINER).fetch(request);
  } catch (error) {
    console.error("container fetch failed", error);
    return json(503, { error: "backend unavailable" });
  }
}

/** Matches the demo's own error shape so HTML and JSON callers agree. */
function respondUnsupported(url: URL, deckUrl: string): Response {
  const message = `unsupported slide URL: ${deckUrl}`;

  if (url.pathname.startsWith("/api/")) return json(422, { error: message });

  return new Response(message, {
    status: 422,
    headers: { "content-type": "text/plain; charset=utf-8" },
  });
}

function json(
  status: number,
  body: unknown,
  extraHeaders: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", ...extraHeaders },
  });
}
