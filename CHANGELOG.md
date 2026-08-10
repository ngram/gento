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

### Known gaps

- The per-site extraction rules are written against documented endpoints and
  conventional markup, not against captured pages. See
  `spec/fixtures/README.md`.
