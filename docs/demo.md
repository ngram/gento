# デモ Web サービス

`web/` は gem の動作を確認するための小さな Sinatra アプリです。
URL を入力するとページ画像を一覧表示します。画像は各サービスのオリジナル URL を
参照するだけで、再ホストはしません。

## 動かす

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

## 閲覧モード

閲覧のしかたは2つあり、右上のボタンで切り替えます。選んだモードは次回も維持されます。

- **一覧** — サムネイルをグリッドに並べる（既定）
- **連続** — 1カラムに大きく縦並べし、スクロールして読む

どちらのモードでも、ページをクリックするとその場でライトボックスが開きます。
`←` `→` でページ送り、`Esc` で閉じます。閉じると直前に見ていたページまでスクロールが戻ります。

JavaScript を切っていても各ページは画像へのリンクとして機能します。

## 環境変数

| 変数 | 既定 | 用途 |
| --- | --- | --- |
| `PORT` | `8080` | 待ち受けポート |
| `GENTO_USER_AGENT` | gem の既定 | 送出する User-Agent を差し替える |
| `GENTO_ROBOTS` | `on` | `off` / `0` / `false` / `no` で robots.txt の参照をやめる |

## Cloudflare へのデプロイ

Workers では Ruby が動かないため、**Worker（TypeScript）を公開窓口に、
Ruby アプリを Cloudflare Containers で動かす**構成にしています。
判断の経緯と ruby.wasm を本命にしなかった理由は
[docs/cloudflare.md](cloudflare.md) に書いています。

```console
$ cd worker && npm ci
$ npx wrangler deploy
```

Containers の利用には Workers Paid プラン（$5/月）が必要です。

コンテナイメージをローカルの Docker で検証する手順は
[docs/verify-container.md](verify-container.md) にまとめています。
手元に Docker がない場合は [docs/codespaces.md](codespaces.md) を参照してください。
