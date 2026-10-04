import { Container } from "@cloudflare/containers";

import { EGRESS_ALLOWLIST } from "./providers";

/**
 * The Ruby demo app, running as a Cloudflare Container.
 *
 * Workers cannot run Ruby, so the gem runs here and the Worker in front acts
 * as the public edge: routing, caching and validation.
 */
export class GentoContainer extends Container<Env> {
  defaultPort = 8080;

  /**
   * Containers bill for wall-clock time while awake, and the Worker's cache
   * absorbs repeat traffic, so there is little value in holding an idle
   * instance. Long enough to serve a burst, short enough not to idle for free.
   */
  sleepAfter = "5m";

  /**
   * The container exists to fetch slide pages from four known sites. Anything
   * else it tries to reach is a bug or a compromise, so block it at the
   * platform rather than trusting application code.
   */
  allowedHosts = EGRESS_ALLOWLIST;

  envVars = {
    RACK_ENV: "production",
    PORT: "8080",
  };

  override onStart(): void {
    console.log("gento container started");
  }

  override onStop(): void {
    console.log("gento container stopped");
  }

  override onError(error: unknown): never {
    console.error("gento container error", error);
    throw error;
  }
}
