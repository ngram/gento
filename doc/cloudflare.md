# Cloudflare で Ruby を動かす — 調査と判断

このリポジトリのデモを Cloudflare に載せるにあたって調べたことと、
最終的に Workers + Containers を選んだ理由をまとめます。
調査時点は 2026年8月です。

## 結論

**Workers 上でネイティブに Ruby は動きません。** 選択肢は3つあり、Containers を採用しました。

| 方式 | 可否 | 判断 |
| --- | --- | --- |
| Workers（ネイティブ Ruby） | ✗ | 一級サポートは JavaScript / TypeScript・Python・Rust。Ruby は対象外 |
| Workers + ruby.wasm | △ | 技術的には可能だが、本番の構成には使わない（後述） |
| **Cloudflare Containers** | ◎ | **採用。** Docker イメージをそのまま動かせ、gem が無改造で動く |

## ruby.wasm を採用しなかった理由

Workers は WebAssembly を実行できるので、CRuby を WebAssembly に移植した
[ruby.wasm](https://github.com/ruby/ruby.wasm) を載せる方法は、理屈の上では成り立ちます。
ただし本番の構成として見ると、次の3つの問題が重なります。

### 1. バンドルサイズ

Workers のスクリプトサイズ上限は Free 3MB / Paid 10MB（gzip 後）、非圧縮で 64MB です。
CRuby 本体と標準ライブラリはこの枠を強く圧迫し、標準ライブラリを削る作業が前提になります。

### 2. ソケットが使えない（最大の問題）

ruby.wasm の WASI ターゲットビルドは**ソケットをサポートしません**。
この gem の仕事は HTTP リクエストでデッキを取得することなので、ソケットが使えなければ機能そのものが成り立ちません。

回避策は、JS interop を通じてホスト側の `fetch` を呼ぶことです。

```ruby
require "js"
JS.global.fetch("https://speakerdeck.com/...").await
```

しかし `await` を使うには Asyncify を有効にしたビルドが必要で、
サイズと実行速度の両方がさらに悪化し、1 のサイズ上限はいっそう厳しくなります。

### 3. 起動コスト

Ruby VM の初期化にかかる時間が、リクエストの処理時間に加わります。CPU 時間に制限のある Workers とは相性がよくありません。

加えて、Wasm Workers Server のような**別の** WebAssembly ランタイムでの Ruby 事例は見つかるものの、
Cloudflare Workers そのものに ruby.wasm を載せた公開事例は見当たりませんでした。
前例のない方法を本番の構成に選ぶのは見送りました。

**ただし、選択肢からは外していません。** gem をネイティブ拡張ゼロ・HTTP 差し替え可能に
設計してあるのは、将来この方法を試せるようにするためです。
`Gento::Fetcher` を JS の `fetch` で実装すれば、ライブラリ本体は改造せずに動く見込みです。
原稿の題材としてはこちらのほうが興味深いので、実験として試す余地を残しています。

## 採用した構成

```
              ┌──────────────────────────────────┐
  request ──▶ │ Worker (TypeScript)              │
              │  - URL 検証（対応サービス判定）  │
              │  - エッジキャッシュ（6時間）     │
              └────────────┬─────────────────────┘
                           │ キャッシュミスのときだけ
                           ▼
              ┌──────────────────────────────────┐
              │ Container (Ruby)                 │
              │  - Sinatra + gento               │
              │  - 外向き通信は4サイトのみ許可   │
              └──────────────────────────────────┘
```

役割分担の意図は次のとおりです。

**Worker で弾けるものは Worker で弾く。** 非対応の URL は、Worker 側のホスト許可リストだけで
判定できます。422 を返すだけのリクエストでコンテナを起動せずに済むので、その分の課金を
避けられます（Containers は起動している時間で課金されます）。

**キャッシュは Worker に置く。** デッキの取得には、外部のスライドサイトとの往復が伴います。
成功レスポンスは 6 時間エッジにキャッシュします。キャッシュのキーは scheme・`www.`・
末尾スラッシュ・`utm_*` を正規化して作り、同じ発表を指す URL の表記ゆれが別のエントリに
ならないようにしています。

**コンテナの外向き通信はプラットフォームで縛る。** `allowedHosts` に4サイトだけを
指定しているので、それ以外への通信は Cloudflare 側でブロックされます。
アプリケーションコードの実装に頼らずに、通信先を制限できます。

**Sinatra 側は puma をスレッドのみ（workers 0）で動かす。** デッキのキャッシュは
プロセス内メモリにあります。ワーカーを増やすと、プロセスごとに別々のキャッシュを持つことになり、
スライドサイトへのリクエストが無駄に増えます。

## 費用

Containers の利用には **Workers Paid プラン（$5/月）** が必要です。
コンテナはリクエストで起動し、アイドル後にスリープするまでの稼働時間で課金されます
（$5 の枠内に月あたりメモリ 25 GiB-hours、CPU 375 vCPU-minutes、ディスク 200 GB-hours が含まれます）。

エッジキャッシュに当たったリクエストではコンテナが起動しないので、コンテナが起動する回数は
キャッシュミスの回数までに抑えられます。デモ用途なら、稼働時間はほぼ無視できる程度に収まる見込みです。

## 無料で済ませたい場合

Cloudflare 完結ではなくなりますが、次の分離構成も取れます。

- フロント: Cloudflare Workers / Pages
- Ruby アプリ: Fly.io / Render / Google Cloud Run

`web/Dockerfile` は特定のプラットフォームに依存しない普通のイメージなので、この切り替えに追加作業はほぼ要りません。

## コンテナの egress 許可リストについて

前述の `allowedHosts` に渡している許可リストの実体は、`worker/src/providers.ts` の
`EGRESS_ALLOWLIST` です。

Google スライドの画像だけは注意が必要です。通常の共有デッキで gem が返す URL は
`docs.google.com` の export エンドポイントですが、実体は `*.googleusercontent.com` への
307 リダイレクトです（ウェブに公開したデッキは `docs.google.com` の viewpage URL を
直接返すのでリダイレクトしません）。
画像を取得するのは閲覧者のブラウザなのでコンテナの許可リストには影響しませんが、
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
