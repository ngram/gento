# 設計方針

**ランタイム依存ゼロ・ネイティブ拡張ゼロ。** HTML の解析に Nokogiri は使わず、
`StringScanner` ベースの小さな HTML スキャナを自前で持っています。
これは削れるものを削った結果ではなく、slim コンテナや ruby.wasm でそのまま動かすための制約です。

**HTTP は差し替え可能。** すべての通信は `Gento::Fetcher` を経由します。
独自の HTTP スタックを持つ環境（Worker の `fetch`、Faraday、テストダブル）では、
net/http を使わずに、その HTTP スタックで実装した `Fetcher` を差し込めます。

```ruby
class MyFetcher < Gento::Fetcher
  def get(url, headers: {})
    # Gento::Response を返し、失敗時は Gento::FetchError を投げる
  end
end

Gento.fetch(url, fetcher: MyFetcher.new)
```

テストもこの仕組みでスタブの `Fetcher` を差し込むので、ソケットを一切開かず、
オフラインの CI でもそのまま動きます。

**壊れにくい情報源から順に見る。** oEmbed → JSON-LD → OpenGraph → HTML の順にフォールバックします。
ページ画像の絞り込みには、CSS クラスではなく、サービスの画像 CDN のホスト名を使います。
クラス名はサイトのリニューアルのたびに変わります。一方、CDN のホスト名は過去の埋め込みにも
書き込まれており、変えるとそれらが表示されなくなるので、まず変わりません。

**対応サービスはクラス1つで追加できる。** `Gento::Adapters::Base` を継承して
`.hosts` と `#fetch` を実装し、レジストリに登録するだけです。

```ruby
Gento::Registry.default.register(MyAdapter)
```

## robots.txt

取得先の `robots.txt` を既定で参照します。`Gento::RobotsFetcher` が
`Fetcher` をラップする形なので、アダプタが出すすべてのリクエストが同じ判定を通ります。
`Fetcher` を差し替えても、この判定はそのまま適用されます。
判定ルールと無効化の手段は [doc/robots.md](robots.md) にまとめています。

## SSRF に対する備え

同梱の `Gento::NetHttpFetcher` は、接続する前に接続先のホスト名を解決し、
プライベートアドレス帯（ループバック、リンクローカル、RFC 1918 など。リンクローカルには
クラウドのメタデータエンドポイントが含まれます）に当たる場合は接続せずに止まります。
この確認はリダイレクト先にも行うので、公開ホストからのリダイレクトで内部ネットワークへ
誘導されることを防げます。任意の URL をユーザから受け取るデモアプリのような用途を想定した、
最低限の防御です。

`NetHttpFetcher` は `HTTPS_PROXY` などのプロキシ用の環境変数も読みます
（net/http は単体では `HTTPS_PROXY` を読みません）。
プライベートアドレス宛ての通信はプロキシを通しません。

## 文字コード

Content-Type ヘッダ → `<meta charset>` → UTF-8 の順に判定し、不正なバイト列は
例外にせず置換します。Shift_JIS や EUC-JP のページも、そのまま扱えます。
