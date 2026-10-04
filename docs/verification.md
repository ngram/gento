# 検証状況と既知の制限

4サービスすべて、`spec/fixtures/` のテストページに対する自動テストが通っており、
実サービスのライブ URL でも end-to-end で動作を確認しています。

`spec/fixtures/` は**このテストスイートのために書き起こしたページ**で、
実ページのキャプチャではありません（[spec/fixtures/README.md](../spec/fixtures/README.md)）。
アダプタが対処すべき構造だけを再現しています。

## サービスごとの注意点

### Speaker Deck

デッキページには他人のデッキのカバー画像も並びます。このデッキ自身の presentation id で
絞り込むことで混入を防いでいます。

### SlideShare

ボット判定で弾かれることがあります（後述）。

### Docswell

デッキページは先頭数ページしか描画しないため、リンクされている embed ビューを読みます。

### Google スライド

通常の共有 URL（`/d/<id>/`）と「ウェブに公開」した `/d/e/<id>/` 形式の両方を実データで
検証済みです。ページ ID の命名には複数の流儀があり（`g<hex>_N_N`、`out_s01`、`p`）、
いずれも確認しています。

**返す画像 URL は、この2形式で種類が違います。**

- 通常の共有デッキ — `export/png` エンドポイント（`*.googleusercontent.com` への
  307 リダイレクト）。有効期限はありません。
- ウェブに公開したデッキ — `export/png` が 404 を返すため、ページに埋め込まれた
  署名付きの `viewpage` URL をそのまま返します。**署名に期限があるので、
  保存せずに速やかに取得してください。**（期限の長さは未計測です）

## SlideShare のボット判定について

SlideShare は、JavaScript を実行しないクライアントに対して、デッキの代わりに
ボット判定用の小さなページを返すことがあります。この場合 gem は「スライドが0枚」ではなく
次のエラーを返します。

```
slide_share: https://www.slideshare.net/slideshow/ansiblenetwork201808/108457145 returned
SlideShare's JavaScript bot challenge instead of the deck. Fetching from SlideShare needs a
JavaScript-capable Gento::Fetcher; the default net/http one cannot get past it.
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

デモアプリは `GENTO_USER_AGENT` で User-Agent を差し替えられるので、
2 を試す前に 1 かどうかを確認できます。

```console
$ docker run --rm -p 8080:8080 \
    -e GENTO_USER_AGENT="Mozilla/5.0 (compatible; gento/0.1.0)" \
    gento-web
```
