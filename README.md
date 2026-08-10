# slidescraper

スライド共有サービスの URL を渡すと、各ページの画像 URL を順番に並べて返す Ruby gem と、
その動作を確認できるデモ Web サービスです。

技術書典5 で頒布した『てっくやみなべ Vol.1』所収
「快適なスライド閲覧⽣活を実現する Web サービスの開発」のサポートリポジトリを、
現在も動く形で作り直したものです。当時の Lambda / PaaS 向けデプロイコードは、
対象サービスが終了したため Cloudflare 向けに置き換えています。

対応サービス: Speaker Deck ・ SlideShare ・ Docswell ・ Google スライド（公開設定のもの）

## gem を使う

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

## 設計方針

**ランタイム依存ゼロ・ネイティブ拡張ゼロ。** Nokogiri をやめて `StringScanner` ベースの
小さな HTML スキャナを自前で持っています。これは削れるものを削ったのではなく、
slim コンテナや ruby.wasm でそのまま動かすための制約です。

**HTTP は差し替え可能。** すべての通信は `Slidescraper::Fetcher` を経由します。
独自の HTTP スタックを持つ環境（Worker の `fetch`、Faraday、テストダブル）は、
net/http を引きずらずにアダプタを差し込めます。

```ruby
class MyFetcher < Slidescraper::Fetcher
  def get(url, headers: {})
    # Slidescraper::Response を返し、失敗時は Slidescraper::FetchError を投げる
  end
end

Slidescraper.scrape(url, fetcher: MyFetcher.new)
```

テストがソケットを一切開かないのもこの設計のおかげで、オフラインの CI でもそのまま動きます。

**壊れにくい順に見る。** oEmbed → JSON-LD → OpenGraph → HTML の順にフォールバックします。
画像の絞り込みは CSS クラスではなくサービスの画像 CDN ホスト名で行います。
クラス名はリニューアルのたびに変わりますが、CDN のホスト名は過去の埋め込みに焼き付いていて、
まず動きません。

**対応サービスの追加はクラス1枚。** `Slidescraper::Adapters::Base` を継承して
`.hosts` と `#scrape` を実装し、レジストリに登録するだけです。

```ruby
Slidescraper::Registry.default.register(MyAdapter)
```

## デモ Web サービス

URL を入力するとページ画像を一覧表示します。画像は各サービスのオリジナル URL を
参照するだけで、再ホストはしません。

```console
$ cd web && bundle install
$ bundle exec puma -C config/puma.rb config.ru
# http://localhost:8080
```

Docker で動かす場合、ビルドコンテキストは**リポジトリのルート**です
（デモが gem を相対パス参照しているため）。

```console
$ docker compose up --build
```

JSON API もあります。

```console
$ curl "http://localhost:8080/api/decks?url=https://speakerdeck.com/user/talk"
```

## Cloudflare へのデプロイ

Workers では Ruby が動かないため、**Worker（TypeScript）を公開窓口に、
Ruby アプリを Cloudflare Containers で動かす**構成にしています。
判断の経緯と ruby.wasm を本命にしなかった理由は
[docs/cloudflare.md](docs/cloudflare.md) に書いています。

```console
$ cd worker && npm ci
$ npx wrangler deploy
```

Containers の利用には Workers Paid プラン（$5/月）が必要です。

## 開発

```console
$ bundle install
$ bundle exec rspec      # gem
$ bundle exec rubocop
$ (cd web && bundle exec rspec)
$ (cd worker && npm test && npm run typecheck)
```

### 現時点の制約

各サービスの抽出ルールは、公開されているエンドポイント仕様と一般的なマークアップ構造に
基づいて書いてあり、**実ページのキャプチャでは検証できていません**
（開発環境から対象サイトへ到達できなかったため）。
`spec/fixtures/` は手書きの合成フィクスチャです。
実 HTML への差し替え手順は [spec/fixtures/README.md](spec/fixtures/README.md) を参照してください。

## ライセンス

MIT License. [LICENSE.txt](LICENSE.txt) を参照してください。
