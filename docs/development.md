# 手元で試す

`main` の最新を手元のマシンで動かして確かめる手順です。
gem・CLI・デモアプリの順に、必要なところまで進めてください。

## 0. 必要なもの

| 試すもの | 必要なもの |
| --- | --- |
| gem・CLI・デモアプリ | Git、Ruby 3.1 以上（CI は 3.1〜3.4 で確認）、Bundler |
| Worker | Node.js 22（CI と同じ） |
| コンテナ | Docker（任意） |

## 1. 取得する

```console
$ git clone https://github.com/ngram/gento.git
$ cd gento
$ git log -1 --oneline    # どのコミットを試しているか
```

すでにクローンしてある場合は、`main` を最新にします。

```console
$ git switch main
$ git pull
```

旧名（slidescraper）の URL でクローンしていても、GitHub がリダイレクトするのでそのまま動きます。
気になる場合は `git remote set-url origin https://github.com/ngram/gento.git` で付け替えてください。

## 2. テストを流す

```console
$ bundle install
$ bundle exec rspec && bundle exec rubocop
$ (cd web && bundle install && bundle exec rspec)
$ (cd worker && npm ci && npm test && npm run typecheck)
```

テストは `Gento::Fetcher` のスタブを使うので、ネットワークには出ません。

`bundler: command not found: rspec` と出る環境では、同梱の binstub を使ってください
（`bin/rspec`、`bin/rubocop`、`web/bin/rspec`）。gem の実行ファイルの置き場が
`PATH` に入っていない環境で起きます。

## 3. CLI で試す

インストールしなくても、リポジトリから直接動かせます。

```console
$ bundle exec exe/gento --format urls https://speakerdeck.com/axbom/what-does-ai-have-to-do-with-human-rights
https://files.speakerdeck.com/presentations/.../slide_0.jpg
https://files.speakerdeck.com/presentations/.../slide_1.jpg
...

$ bundle exec exe/gento https://speakerdeck.com/axbom/what-does-ai-have-to-do-with-human-rights
{
  "provider": "speaker_deck",
  "title": "What does AI have to do with Human Rights?",
  "page_count": 50,
  ...
}

$ bundle exec exe/gento --help
```

**ここから先は、実際に各サービスへアクセスします。** `robots.txt` は既定で参照します
（[docs/robots.md](robots.md)）。対象サービスの利用規約の確認は利用者の責任です
（[docs/legal.md](legal.md)）。

4サービスそれぞれのサンプル URL と、期待するページ数は
[docs/verify-container.md](verify-container.md#4-4-実際に取得できること) にあります。
SlideShare はデータセンターの IP からだと弾かれますが、家庭用回線からなら通ることが多いです
（[docs/verification.md](verification.md#slideshare-のボット判定について)）。

## 4. Ruby から試す

```console
$ bundle exec irb -r gento
>> deck = Gento.fetch("https://speakerdeck.com/axbom/what-does-ai-have-to-do-with-human-rights")
>> deck.page_count
=> 50
>> deck.slides.first.url
=> "https://files.speakerdeck.com/presentations/.../slide_0.jpg"
```

## 5. gem としてインストールして試す

RubyGems.org にはまだ公開していないので、`gem install gento` では入りません。
手元でビルドしてインストールします。

```console
$ gem build gento.gemspec
$ gem install ./gento-0.1.0.gem
$ gento --version
0.1.0
```

元に戻すときは `gem uninstall gento` です。

## 6. 別のプロジェクトから使う

試したいプロジェクトの Gemfile に、GitHub の `main` を直接書きます。

```ruby
gem "gento", github: "ngram/gento", branch: "main"
```

`bundle install` した時点の `main` のコミットが Gemfile.lock に固定されます。
その後の `main` を取り込むときは `bundle update gento` を実行します。

手元のクローンを直接参照する場合は、パスで指定します。

```ruby
gem "gento", path: "../gento"
```

## 7. デモアプリを動かす

```console
$ cd web
$ bundle install
$ bundle exec puma -C config/puma.rb config.ru
```

http://localhost:8080 を開いて URL を入力します。止めるときは `Ctrl-C` です。
ポート 8080 が使われている場合は、`PORT=9292` のように `PORT` を付けて起動してください。

JSON API でも確認できます。

```console
$ curl -sG --data-urlencode "url=https://speakerdeck.com/axbom/what-does-ai-have-to-do-with-human-rights" \
    localhost:8080/api/decks
```

環境変数は [docs/demo.md](demo.md#環境変数) にまとめています。

Docker で動かす場合は、リポジトリのルートで実行します。

```console
$ docker compose up --build
```

コンテナで確認する項目（非 root での実行、ヘルスチェックなど）は
[docs/verify-container.md](verify-container.md) にあります。

## 8. Worker を動かす（任意）

```console
$ cd worker
$ npm ci
$ npx wrangler dev
```

http://localhost:8787 で待ち受けます。Containers のローカル実行には Docker が必要で、
挙動に癖があります。まずは 7. のデモアプリ単体で確認するほうが確実です。
Cloudflare へのデプロイは [docs/demo.md](demo.md#cloudflare-へのデプロイ) を参照してください。

## つまずきやすいところ

**`bundler: command not found: rspec`（`puma` なども）**
gem の実行ファイルの置き場が `PATH` に入っていません。`bin/` の binstub を使うか、
`PATH="$(ruby -e 'print Gem.bindir'):$PATH"` を付けて実行してください。

**SlideShare だけ `ExtractionError`（bot challenge）になる**
接続元 IP の評価で弾かれています。gem 側の問題ではありません
（[docs/verification.md](verification.md#slideshare-のボット判定について)）。

**`RobotsDisallowedError` になる**
取得先の `robots.txt` が拒否しているか、`robots.txt` 自体を読めなかった（5xx・429・接続失敗）
ときに起きます。判定のルールは [docs/robots.md](robots.md) を参照してください。
