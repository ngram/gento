# Fixtures

**These pages are written for this test suite. None of them is a copy of a real
page from any of the supported services.**

They are small on purpose — a handful of pages each, readable in a diff — and
each one reproduces a structural pattern the adapters have to cope with:

| Fixture | What it exercises |
| --- | --- |
| `speaker_deck/deck.html` | pages linked from `<a href>`; the deck id on a nested `<div data-id>`; a cache-busting query on one page; two *other* decks' preview images that must not be picked up |
| `speaker_deck/oembed.json` | title and author coming from oEmbed rather than the page |
| `slide_share/deck.html` | CDN filenames carrying page number and width; one page offered at several widths; an avatar on the same CDN that is not a page; JSON-LD metadata |
| `slide_share/challenge.html` | the two markers the bot-challenge detector matches |
| `docswell/deck.html` | the embed link (plain and `?mode=extend`); only the first pages present |
| `docswell/embed.html` | every page, each appearing twice — full size and `?width=160` |
| `docswell/oembed.json` | the author name, which the deck page does not carry |
| `google_slides/htmlpresent.html` | one signed `viewpage` URL per page, ids shaped `g<hex>_N_N` |
| `google_slides/htmlpresent-outline-ids.html` | the same, with ids shaped `out_s01` and `p` |
| `google_slides/htmlpresent-published.html` | a published (`/d/e/`) deck, where only the signed URLs work |

## Changing them

Edit the fixture and the expectation together. The specs assert page counts and
exact URLs, so a fixture change that is not reflected in the spec fails loudly,
which is the intent.

If a site changes its markup, reproduce the *shape* of the change here by hand.
Do not paste a captured page in: these files are distributed with the
repository, and the pages of a slide service are somebody else's work.
