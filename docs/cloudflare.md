# Cloudflare で Ruby を動かす — 調査と判断

このリポジトリのデモを Cloudflare に載せるにあたって調べたことと、
最終的に Workers + Containers を選んだ理由をまとめます。
調査時点は 2026年8月です。

## 結論

**Workers 上でネイティブに Ruby は動きません。** 選択肢は3つあり、本命は Containers です。

| 方式 | 可否 | 判断 |
| --- | --- | --- |
| Workers（ネイティブ Ruby） | ✗ | 一級サポートは JavaScript / TypeScript・Python・Rust。Ruby は対象外 |
| Workers + ruby.wasm | △ | 技術的には可能だが本番経路にはしない（後述） |
| **Cloudflare Containers** | ◎ | **採用。** Docker イメージをそのまま動かせ、gem が無改造で動く |

## ruby.wasm を本命にしなかった理由

Workers は WebAssembly を実行できるので、CRuby を WebAssembly に移植した
[ruby.wasm](https://github.com/ruby/ruby.wasm) を載せる道は理屈の上では存在します。
ただし本番経路として見ると、次の3つが重なります。

### 1. バンドルサイズ

Workers のスクリプトサイズ上限は Free 3MB / Paid 10MB（gzip 後）、非圧縮で 64MB です。
CRuby 本体と標準ライブラリはこの枠を強く圧迫し、標準ライブラリを削る作業が前提になります。

### 2. ネットワークが出ない（これが致命的）

ruby.wasm の WASI ターゲットビルドは**ソケットをサポートしません**。
スクレイピングは HTTP リクエストが仕事の中身なので、これは機能そのものが成立しないことを意味します。

回避策は JS interop 経由でホストの `fetch` を借りることです。

```ruby
require "js"
JS.global.fetch("https://speakerdeck.com/...").await
```

しかし `await` を使うには Asyncify を有効にしたビルドが必要で、
サイズと実行速度の両方がさらに悪化します。1 の制約と正面から衝突します。

### 3. 起動コスト

Ruby VM の初期化がリクエストごとに乗ります。Workers の CPU 時間制限と相性が良くありません。

加えて、Wasm Workers Server のような**別の** WebAssembly ランタイムでの Ruby 事例は見つかるものの、
Cloudflare Workers そのものに ruby.wasm を載せた公開事例は見当たりませんでした。
前例のない道を本番経路にする理由はありません。

**ただし完全に捨ててはいません。** gem 側をネイティブ拡張ゼロ・HTTP 差し替え可能に
設計してあるのは、この道を将来試せるようにするためです。
`Slidescraper::Fetcher` を JS の `fetch` で実装すれば、ライブラリ本体は無改造で載ります。
原稿のネタとしてはこちらの方が面白いので、実験枠として残しています。

## 採用した構成

```
              ┌──────────────────────────┐
  request ──▶ │ Worker (TypeScript)      │
              │  - URL 検証（対応サービス判定） │
              │  - エッジキャッシュ (6h)      │
              └───────────┬──────────────┘
                          │ キャッシュミスのときだけ
                          ▼
              ┌──────────────────────────┐
              │ Container (Ruby)         │
              │  - Sinatra + slidescraper │
              │  - egress は4サイトのみ許可   │
              └──────────────────────────┘
```

役割分担の意図は次のとおりです。

**Worker で弾けるものは Worker で弾く。** 非対応 URL の判定は Worker 側の
ホスト許可リストで完結します。どうせ 422 になるリクエストのためにコンテナを
起こす必要はありません（Containers は起動している時間で課金されます）。

**キャッシュは Worker に置く。** スクレイピングは他所のサイトへの往復コストです。
成功レスポンスは 6 時間エッジにキャッシュし、キーは scheme・`www.`・末尾スラッシュ・
`utm_*` を正規化して、同じ発表を指す URL のゆらぎが別エントリにならないようにしています。

**コンテナの外向き通信はプラットフォームで縛る。** `allowedHosts` に4サイトだけを
指定しているので、それ以外への通信は Cloudflare 側でブロックされます。
アプリケーションコードの自制に頼りません。

**Sinatra 側は puma をスレッドのみ（workers 0）で動かす。** デッキのキャッシュが
プロセス内メモリにあるため、ワーカーを増やすとキャッシュが複製されて
スライドサイトへのリクエストが無駄に増えます。

## 費用

Containers の利用には **Workers Paid プラン（$5/月）** が必要です。
コンテナはリクエストで起動し、アイドル後にスリープするまでの稼働時間で課金されます
（$5 の枠内に月あたりメモリ 25 GiB-hours、CPU 375 vCPU-minutes、ディスク 200 GB-hours が含まれます）。

エッジキャッシュが効いている限り、コンテナが起きる回数は「キャッシュミスの回数」まで落ちます。
デモ用途ならこの構成でほぼ無視できる稼働時間に収まるはずです。

## 無料で済ませたい場合

Cloudflare 完結ではなくなりますが、次の分離構成も取れます。

- フロント: Cloudflare Workers / Pages
- Ruby アプリ: Fly.io / Render / Google Cloud Run

`web/Dockerfile` はどこにでも載る普通のイメージなので、この切り替えに追加作業はほぼ不要です。

## コンテナの egress 許可リストについて

`worker/src/providers.ts` の `EGRESS_ALLOWLIST` が、コンテナから出られる先を縛っています。
スクレイピング対象の4サイトだけを許可しているので、それ以外への通信は
Cloudflare 側でブロックされます。

Google スライドの画像だけは注意が必要です。通常の共有デッキで gem が返す URL は
`docs.google.com` の export エンドポイントですが、実体は `*.googleusercontent.com` への
307 リダイレクトです（ウェブに公開したデッキは `docs.google.com` の viewpage URL を
直接返すのでリダイレクトしません）。
画像を読むのは閲覧者のブラウザなのでコンテナの許可リストには影響しませんが、
将来サーバー側で画像を取得する処理を足す場合は `*.googleusercontent.com` の追加が必要になります。

## 未検証の項目

- **コンテナイメージのビルド**: 開発環境に Docker デーモンがなく、`web/Dockerfile` は
  ビルドできていません。設定の妥当性は `wrangler deploy --dry-run` まで確認済みです
  （バインディングと Dockerfile の解決は成功）。
- **実デプロイ**: Cloudflare アカウントに対する `wrangler deploy` は未実行です。

## 参考

- [Languages · Cloudflare Workers docs](https://developers.cloudflare.com/workers/languages/)
- [WebAssembly (Wasm) · Cloudflare Workers docs](https://developers.cloudflare.com/workers/runtime-apis/webassembly/)
- [Limits · Cloudflare Workers docs](https://developers.cloudflare.com/workers/platform/limits/)
- [Overview · Cloudflare Containers docs](https://developers.cloudflare.com/containers/)
- [Containers are available in public beta](https://blog.cloudflare.com/containers-are-available-in-public-beta-for-simple-global-and-programmable/)
- [ruby/ruby.wasm](https://github.com/ruby/ruby.wasm)
- [Wasm Workers Server 1.0: support for Python and Ruby](https://wasmlabs.dev/articles/wasm-workers-server-1-0-0/)
