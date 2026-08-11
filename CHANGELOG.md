# Changelog

## Unreleased

### Added

- `Slidescraper::Client#scrape`, which turns a slide URL into a `Deck` of
  ordered page images.
- Adapters for Speaker Deck, SlideShare, Docswell and public Google Slides.
- A pure-Ruby HTML scanner, so the gem carries no native extensions and no
  runtime dependencies.
- A pluggable `Fetcher` seam, with a net/http implementation that guards
  against redirects into private address ranges.
- Charset detection, so Shift_JIS and EUC-JP decks decode correctly.
- `slidescraper` CLI, printing JSON or one image URL per line.

- Proxy support in the net/http fetcher, honouring `HTTPS_PROXY` (which
  net/http ignores on its own) and bypassing it for private addresses.

### Fixed

- The tag scanner consumed element content, so a tag nested inside another of
  the same name was invisible — which is most of the markup on a real page.
- Typographic entities such as `&hellip;` and `&mdash;` were left undecoded.
- Titles carrying the author's own line breaks are collapsed to single spaces.

### Known gaps

- Google Slides decks published to the web (`/d/e/<id>/` URLs) have a code
  path but no verification; ordinary shared decks are verified.
- SlideShare intermittently answers with a bot interstitial. It is detected
  and reported as such, but getting past it needs a JavaScript-capable
  `Fetcher`.
