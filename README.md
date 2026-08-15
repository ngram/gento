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

閲覧のしかたは2つあり、右上のボタンで切り替えます。選んだモードは次回も維持されます。

- **一覧** — サムネイルをグリッドに並べる（既定）
- **連続** — 1カラムに大きく縦並べし、スクロールして読む

どちらのモードでも、ページをクリックするとその場でライトボックスが開きます。
`←` `→` でページ送り、`Esc` で閉じます。閉じると直前に見ていたページまでスクロールが戻ります。

JavaScript を切っていても各ページは画像へのリンクとして機能します。

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

コンテナイメージをローカルの Docker で検証する手順は
[docs/verify-container.md](docs/verify-container.md) にまとめています。
手元に Docker がない場合は [docs/codespaces.md](docs/codespaces.md) を参照してください。
`.devcontainer/` を同梱しているので、GitHub Codespaces を起動すれば
Docker とデプロイまで含めて iPhone だけで検証できます。

## 開発

```console
$ bundle install
$ bundle exec rspec      # gem          97 examples
$ bundle exec rubocop
$ (cd web && bundle exec rspec)                 # デモアプリ 16 examples
$ (cd worker && npm test && npm run typecheck)  # Worker     15 tests
```

GitHub Codespaces なら `.devcontainer/` が上記をすべて用意します
（[docs/codespaces.md](docs/codespaces.md)）。

### 検証状況

4サービスすべて、実ページのキャプチャに対してテストが通っており、
ライブの実 URL でも end-to-end で動作を確認しています。
`spec/fixtures/` は実際に配信されたページをそのまま保存したものです
（[spec/fixtures/README.md](spec/fixtures/README.md)）。

既知の注意点:

- **SlideShare はボット判定で弾かれることがあります**（後述）。
- **Google スライド** は通常の共有 URL（`/d/<id>/`）と「ウェブに公開」した
  `/d/e/<id>/` 形式の両方を実データで検証済みです。ページ ID の命名には複数の流儀があり
  （`g<hex>_N_N`、`out_s01`、`p`）、いずれも確認しています。
- **Google スライドが返す画像 URL は、この2形式で種類が違います。**
  通常の共有デッキは `export/png` エンドポイント（`*.googleusercontent.com` への
  307 リダイレクト）で、有効期限がありません。
  ウェブに公開したデッキは `export/png` が 404 を返すため、
  ページに埋め込まれた署名付きの `viewpage` URL をそのまま返します。
  こちらは署名に期限があるので、保存せずに速やかに取得してください。

### SlideShare のボット判定について

SlideShare は、JavaScript を実行しないクライアントに対して、デッキの代わりに
ボット判定用の小さなページを返すことがあります。この場合 gem は「スライドが0枚」ではなく
次のエラーを返します。

```
slide_share: https://www.slideshare.net/slideshow/ansiblenetwork201808/108457145 returned
SlideShare's JavaScript bot challenge instead of the deck. Scraping SlideShare needs a
JavaScript-capable Slidescraper::Fetcher; the default net/http one cannot get past it.
```

**判定はリクエストの内容ではなく、接続元 IP の評価で決まります。** そのため同じ URL が
家庭用回線からは取得できても、データセンターの IP からは恒常的に弾かれます。
Codespaces（Azure）、CI ランナー、クラウド上のコンテナが該当します。
User-Agent やヘッダを変えても通りません。**これは仕様上どうにもならない部分です。**

原因の切り分けは、gem を通さず直接叩けば分かります。

```console
$ curl -sS "https://www.slideshare.net/slideshow/ansiblenetwork201808/108457145" \
    | grep -c "Client Challenge"
1     # ← 1 なら、この環境の IP が弾かれています（gem 側の問題ではありません）
0     # ← 0 なら通っているので、User-Agent など gem 側の要因
```

取れる対応は3つです。

1. **家庭用回線から実行する。** 同じイメージでもローカルの Docker なら通ることが多いです。
2. **JavaScript を実行できる `Fetcher` を差し込む。** 設計上の正規ルートで、gem 本体は無改造で
   載ります。ヘッドレスブラウザ一式が必要になります。
3. **SlideShare を使わない。** 他の3サービスはこの制限を受けません。

デモアプリは `SLIDESCRAPER_USER_AGENT` で User-Agent を差し替えられるので、
2 を試す前に 1 かどうかを確認できます。

```console
$ docker run --rm -p 8080:8080 \
    -e SLIDESCRAPER_USER_AGENT="Mozilla/5.0 (compatible; slidescraper/0.1.0)" \
    slidescraper-web
```

## 利用にあたっての注意

**対象サービスの利用規約を確認し、遵守する責任は利用者にあります。**
[docs/legal.md](docs/legal.md) を読んでから使ってください。

## ライセンス

MIT License. [LICENSE.txt](LICENSE.txt) を参照してください。
