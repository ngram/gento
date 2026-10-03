# 設計方針

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

## robots.txt

取得先の `robots.txt` を既定で参照します。`Slidescraper::RobotsFetcher` が
`Fetcher` をラップする形なので、アダプタが出すすべてのリクエストが同じ判定を通り、
差し替えられた `Fetcher` の上でも同じように効きます。
判定ルールと無効化の手段は [docs/robots.md](robots.md) にまとめています。

## SSRF に対する備え

同梱の `Slidescraper::NetHttpFetcher` は、リダイレクト先がプライベートアドレス帯
（ループバック、リンクローカル、RFC1918、クラウドのメタデータ endpoint）に入る場合に
そこで停止します。任意の URL をユーザから受け取るデモアプリのような用途を想定した
最低限の防御です。

`HTTPS_PROXY` などの環境変数も見ます（net/http は自分では見ません）。
プライベートアドレス宛てはプロキシを迂回します。

## 文字コード

Content-Type ヘッダ → `<meta charset>` → UTF-8 の順に判定し、不正なバイト列は
例外にせず置換します。Shift_JIS や EUC-JP のページも、そのまま扱えます。
