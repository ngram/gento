# Fixtures

**These fixtures are synthetic.** They were hand-written to encode the page
structure each adapter expects, not captured from the live sites — the
environment this code was first written in could not reach speakerdeck.com,
slideshare.net, docswell.com or docs.google.com.

They are still useful: they pin the parsing contract, so a change that breaks
`Html` or an adapter's extraction order fails the suite. What they cannot do is
prove the contract matches reality.

## Replacing them with real captures

```sh
curl -sSL -A "slidescraper-fixture-capture" \
  "https://speakerdeck.com/<user>/<slug>" \
  -o spec/fixtures/speaker_deck/deck.html
```

Capture each file listed below, re-run `bundle exec rspec`, and fix whatever
the real markup breaks. Trim analytics/inline-CSS noise if the file is huge,
but never hand-edit the parts an adapter reads.

| Fixture | Source |
| --- | --- |
| `speaker_deck/deck.html` | `https://speakerdeck.com/<user>/<slug>` |
| `speaker_deck/oembed.json` | `https://speakerdeck.com/oembed.json?url=<deck url>` |
| `speaker_deck/player.html` | `https://speakerdeck.com/player/<deck id>` |
| `slide_share/deck.html` | `https://www.slideshare.net/<user>/<slug>` |
| `docswell/deck.html` | `https://www.docswell.com/s/<user>/<id>-<slug>` |
| `google_slides/embed.html` | `https://docs.google.com/presentation/d/<id>/embed` |
| `google_slides/deck.html` | `https://docs.google.com/presentation/d/<id>/edit` |
