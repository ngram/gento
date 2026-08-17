# robots.txt の扱い

**既定で ON です。** 取得先ホストの `robots.txt` を読み、拒否されているパスにはリクエストを
送りません。RFC 9309 に沿って実装しています。

対象はデッキページだけではありません。`Slidescraper::RobotsFetcher` が
`Slidescraper::Fetcher` をラップする形になっているので、**アダプタが出すすべてのリクエスト**
（oEmbed エンドポイント、Docswell の embed ビュー、Google スライドの `/htmlpresent`）が
同じ判定を通ります。

## 無効化

```ruby
Slidescraper.scrape(url, robots: false)
Slidescraper::Client.new(robots: false)
```

```console
$ slidescraper --no-robots URL
```

デモアプリは環境変数で切り替えます（既定 ON）。

```console
$ docker run -e SLIDESCRAPER_ROBOTS=off ... slidescraper-web
```

**無効化した場合、その判断と結果は利用者の責任です。**
[docs/legal.md](legal.md) を参照してください。

## 判定ルール

### 最長一致が勝ちます

ここが実装上いちばん重要な点です。Google の `robots.txt` は末尾がこうなっています。

```
Allow: /presentation
...
Disallow: /
```

**先頭から順に見て最初に一致したものを採用する実装だと、Google スライドは全滅します。**
RFC 9309 が定めるとおり、一致したパターンのうち**最も長いもの**を採用します
（`/presentation` は13文字、`/` は1文字なので Allow が勝つ）。
同じ長さで Allow と Disallow が衝突した場合は Allow です。

### パターン

- `*` は任意の文字列
- `$` は末尾の固定
- それ以外は前方一致（`Disallow: /api/` は `/api/decks?url=x` に一致）
- 判定対象はパスとクエリの両方（`Disallow: /search?` は `/search?q=x` に一致し `/search` には一致しない）
- 値が空の `Disallow:` は「制限なし」の意味なので、規則として扱いません

### User-agent グループ

自分を名指ししているグループが1つだけ適用され、なければ `*` のグループが使われます。
突き合わせるのは User-Agent 文字列全体ではなく**プロダクトトークン**
（最初のスラッシュまで。`slidescraper/0.1.0 (+https://github.com/ngram/slidescraper)`
なら `slidescraper`）です。文字列全体で部分一致させると、UA に含まれる URL のせいで
無関係なグループに巻き込まれます。

`SLIDESCRAPER_USER_AGENT` や `--user-agent` で名乗りを変えると、**適用されるグループも変わります。**
たとえば SlideShare は複数のクローラを名指しで全面拒否しているので、それらに一致する名前を
名乗れば、その時点で全ページが拒否されます。

## robots.txt を読めなかったとき

| 応答 | 扱い |
| --- | --- |
| 2xx | 内容に従う |
| 404 その他の 4xx | robots.txt が無い → **全て許可** |
| 429 | 「後で来い」であって「無い」ではない → **全て拒否** |
| 5xx | **全て拒否** |
| 接続失敗・タイムアウト | **全て拒否** |

読めなかったことは許可ではない、というのが RFC 9309 §2.3.1.4 の立場で、それに従っています。
一時的な 5xx でスクレイプが失敗しうるということでもあるので、エラーメッセージには
`robots: false` で回避できることを書いてあります。

## Content-Type は見ていません

本文は Content-Type に関係なくパースします。

Speaker Deck は `Accept: text/plain` を送らないと `/robots.txt` を**サイトの HTML レイアウトに
包んで返します**（`content-type: text/html`）。中身は本物の `robots.txt` です。
Content-Type だけで弾く実装だと、この本物の規則を捨ててしまいます。

そのため gem は `Accept: text/plain` を送ったうえで、返ってきた本文をそのままパースします。
`robots.txt` ではない普通の HTML ページからは、そもそも規則が1つも取れません
（`User-agent:` 行が先に無いと規則は成立しないため）。

## Crawl-delay

パースして `RobotsFetcher#crawl_delay(url)` で取得できますが、**自動では待ちません。**
1回の `scrape` が出すリクエストは数件で、フェッチャの内側で `sleep` するのは、
自分でペース配分をしている呼び出し側にとって予想外の挙動になるためです。
複数デッキをまとめて処理する場合は、この値を見て呼び出し側で待ってください。

```ruby
fetcher = Slidescraper::RobotsFetcher.new(Slidescraper::NetHttpFetcher.new)
fetcher.crawl_delay("https://docs.google.com/presentation/d/x/htmlpresent")  # => 1.0
```

## 各サービスの実際の内容

2026年8月時点で実際に取得して確認した結果です。**4サービスとも、この gem がやっている
取得は許可されています。**

| サービス | 内容 | この gem への影響 |
| --- | --- | --- |
| Speaker Deck | `/*signin?*`、`/*.atom*` など6件を拒否。`Accept: text/plain` が必要 | なし |
| SlideShare | 11グループ。`*` グループは `/api/`、`/search/`、`/slideshow/embed_code/` などを拒否。複数のクローラを名指しで全面拒否 | なし（デッキページは許可） |
| Docswell | `Disallow: /slide/*/download` の1件のみ | なし（embed ビューは許可） |
| Google スライド | `Allow: /presentation` ＋ `Disallow: /`、`Crawl-delay: 1` | なし（最長一致で許可） |

内容は変わりうるので、これは保証ではありません。手元で確かめるには:

```console
$ curl -sS -H "Accept: text/plain" https://speakerdeck.com/robots.txt
```

## 限界

**リダイレクト先はチェックしていません。** リダイレクトの追跡はラップされた側の
`Fetcher` が内部で行うため、拒否されたパスへリダイレクトされた場合は素通りします。
これを塞ぐには `Fetcher` にホップごとのコールバックを持たせる必要があり、
追加するインタフェースに見合わないと判断しました。

**`robots.txt` は画像の取得までは縛れません。** この gem が返すのは画像 URL であって、
画像自体は取得しないためです。返された URL を実際に取得する場合は、
そのホスト（`files.speakerdeck.com` など）の `robots.txt` は別途確認してください。
