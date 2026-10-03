# slidescraper

スライド共有サービスの URL を渡すと、各ページの画像 URL を順番に並べて返す Ruby gem です。

対応サービス: Speaker Deck ・ SlideShare ・ Docswell ・ Google スライド（公開設定のもの）

ランタイム依存ゼロ・ネイティブ拡張ゼロで動きます。

## インストール

```console
$ gem install slidescraper
```

Gemfile なら:

```ruby
gem "slidescraper"
```

## 使いかた

```ruby
require "slidescraper"

deck = Slidescraper.scrape("https://speakerdeck.com/user/talk")

deck.title       # => "快適なスライド閲覧生活を実現する Web サービスの開発"
deck.author      # => "ngram"
deck.page_count  # => 42
deck.slides.map(&:url)
# => ["https://files.speakerdeck.com/.../slide_0.jpg", ...]
```

`Deck` と `Slide` は不変オブジェクトで、`to_h` / `to_json` でそのまま出力できます。

対応している URL かどうかは、取得する前に確認できます。

```ruby
Slidescraper.supports?("https://speakerdeck.com/user/talk")  # => true
```

### コマンドライン

```console
$ slidescraper https://speakerdeck.com/user/talk
{
  "provider": "speaker_deck",
  "source_url": "https://speakerdeck.com/user/talk",
  "title": "...",
  "page_count": 42,
  "slides": [ ... ]
}

$ slidescraper --format urls https://speakerdeck.com/user/talk
https://files.speakerdeck.com/presentations/.../slide_0.jpg
...
```

### robots.txt

**取得先の `robots.txt` を既定で参照し、拒否されているパスは取りに行きません。**
デッキページだけでなく、アダプタが出すすべてのリクエスト（oEmbed、embed ビューなど）が対象です。

```ruby
Slidescraper.scrape(url)                 # robots.txt に従う（既定）
Slidescraper.scrape(url, robots: false)  # 従わない（判断は利用者の責任）
```

```console
$ slidescraper --no-robots https://speakerdeck.com/user/talk
```

拒否された場合は `Slidescraper::RobotsDisallowedError` になります。
`robots.txt` 自体を読めなかったとき（5xx・429・接続失敗）も、RFC 9309 に従って拒否扱いです。

詳細は [docs/robots.md](docs/robots.md) を参照してください。

### HTTP クライアントの差し替え

通信はすべて `Slidescraper::Fetcher` を経由するので、独自の HTTP スタックを差し込めます。

```ruby
Slidescraper.scrape(url, fetcher: MyFetcher.new)
```

詳細は [docs/design.md](docs/design.md) を参照してください。

### エラー

| 例外 | 起きるとき |
| --- | --- |
| `Slidescraper::UnsupportedURLError` | 対応アダプタのない URL |
| `Slidescraper::RobotsDisallowedError` | `robots.txt` が許可していない（`FetchError` の一種） |
| `Slidescraper::FetchError` | 取得に失敗（`ResponseError` を含む） |
| `Slidescraper::ExtractionError` | 取得はできたがページを取り出せない |

いずれも `Slidescraper::Error` を継承しています。

**SlideShare は接続元 IP によってボット判定で弾かれることがあり**、その場合は
`ExtractionError` になります。データセンターの IP からは恒常的に弾かれます
（[docs/verification.md](docs/verification.md#slideshare-のボット判定について)）。

## 利用にあたっての注意

**対象サービスの利用規約を確認し、遵守する責任は利用者にあります。**
[docs/legal.md](docs/legal.md) を読んでから使ってください。

## ドキュメント

- [robots.txt の扱い](docs/robots.md) — 判定ルール、無効化、各サービスの実際の内容
- [設計方針](docs/design.md) — 依存ゼロにした理由、Fetcher の差し替え、アダプタの足し方
- [検証状況と既知の制限](docs/verification.md) — サービスごとの注意点、SlideShare のボット判定
- [デモ Web サービス](docs/demo.md) — `web/` の動かしかたと Cloudflare へのデプロイ
- [利用にあたっての注意](docs/legal.md)
- [RubyGems への公開手順](docs/publishing.md)

## 開発

```console
$ bundle install
$ bundle exec rspec      # gem         151 examples
$ bundle exec rubocop
$ (cd web && bundle exec rspec)                 # デモアプリ 27 examples
$ (cd worker && npm test && npm run typecheck)  # Worker     15 tests
```

GitHub Codespaces なら `.devcontainer/` が上記をすべて用意します
（[docs/codespaces.md](docs/codespaces.md)）。

## 由来

技術書典5 で頒布した『てっくやみなべ Vol.1』所収
「快適なスライド閲覧⽣活を実現する Web サービスの開発」のサポートリポジトリを、
現在も動く形で作り直したものです。当時の Lambda / PaaS 向けデプロイコードは、
対象サービスが終了したため Cloudflare 向けに置き換えています。

## ライセンス

MIT License. [LICENSE.txt](LICENSE.txt) を参照してください。
