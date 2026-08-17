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

- robots.txt, obeyed by default (RFC 9309). A `RobotsFetcher` wraps whatever
  fetcher is in use, so every request an adapter makes is checked, not just
  the deck page. `robots: false`, `--no-robots` and `SLIDESCRAPER_ROBOTS=off`
  turn it off. A robots.txt that cannot be read is treated as a refusal
  rather than as permission.

- Proxy support in the net/http fetcher, honouring `HTTPS_PROXY` (which
  net/http ignores on its own) and bypassing it for private addresses.

- The demo's viewer: a lightbox on clicking a page, with arrow-key paging,
  and a switch between the thumbnail grid and a continuous vertical read.
  The choice is remembered. Built on `<dialog>` with no dependencies, and
  layered over markup that still works with JavaScript off.
- `SLIDESCRAPER_USER_AGENT`, so a deployed container can change how it
  identifies itself without a rebuild.

### Fixed

- The tag scanner consumed element content, so a tag nested inside another of
  the same name was invisible — which is most of the markup on a real page.
- Typographic entities such as `&hellip;` and `&mdash;` were left undecoded.
- Titles carrying the author's own line breaks are collapsed to single spaces.

- Google Slides decks published to the web return the signed `viewpage` URLs
  embedded in the document. `/export/png` answers 404 for those decks, so the
  URLs it would have built were unusable. Ordinary shared decks keep using
  `/export/png`, which does not expire.

### Known gaps

- SlideShare's bot protection decides on the caller's IP reputation, so from
  a datacenter address it can refuse every request. Detected and reported as
  itself; getting past it needs a JavaScript-capable `Fetcher`.
- The signed `viewpage` URLs returned for published Google Slides decks
  expire; how long they last has not been measured.
- The robots.txt check does not follow redirects: the wrapped fetcher handles
  those internally, so a redirect into a disallowed path is not caught.
