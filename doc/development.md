# 手元で試す

`main` の最新を手元のマシンで動かして確かめる手順です。
gem・CLI・デモアプリの順に、必要なところまで進めてください。

## 0. 必要なもの

| 試すもの | 必要なもの |
| --- | --- |
| gem・CLI・デモアプリ | Git、Ruby 3.1 以上（CI は 3.1〜3.4 で確認）、Bundler |
| Worker | Node.js 22（CI と同じ） |
| コンテナ | Docker（任意） |

Windows では手順が一部変わります。[Windows の場合](#windows-の場合) も参照してください。

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
`PATH` に入っていない macOS・Linux の環境で起きます。Windows では binstub は使えませんが、
`bundle exec rspec` がそのまま動きます。

## 3. CLI で試す

インストールしなくても、リポジトリから直接動かせます。
`ruby` を通して起動しているのは、Windows では拡張子のない `exe/gento` をそのまま実行できないためです。
macOS・Linux でも同じコマンドで動きます。

```console
$ bundle exec ruby exe/gento --format urls https://speakerdeck.com/axbom/what-does-ai-have-to-do-with-human-rights
https://files.speakerdeck.com/presentations/.../slide_0.jpg
https://files.speakerdeck.com/presentations/.../slide_1.jpg
...

$ bundle exec ruby exe/gento https://speakerdeck.com/axbom/what-does-ai-have-to-do-with-human-rights
{
  "provider": "speaker_deck",
  "title": "What does AI have to do with Human Rights?",
  "page_count": 50,
  ...
}

$ bundle exec ruby exe/gento --help
```

**ここから先は、実際に各サービスへアクセスします。** `robots.txt` は既定で参照します
（[doc/robots.md](robots.md)）。対象サービスの利用規約の確認は利用者の責任です
（[doc/legal.md](legal.md)）。

4サービスそれぞれのサンプル URL と、期待するページ数は
[doc/verify-container.md](verify-container.md#4-4-実際に取得できること) にあります。
SlideShare はデータセンターの IP からだと弾かれますが、家庭用回線からなら通ることが多いです
（[doc/verification.md](verification.md#slideshare-のボット判定について)）。

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

RubyGems.org に公開済みの版は `gem install gento` で入ります。`main` の最新を試すときは、
手元でビルドしてインストールします。`gem install --local gento` は、今いるフォルダにある
`gento-*.gem` を探して入れるので、版の番号を書かずに済みます。

```console
$ gem build gento.gemspec
$ gem install --local gento
$ gento --version
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

環境変数は [doc/demo.md](demo.md#環境変数) にまとめています。

Docker で動かす場合は、リポジトリのルートで実行します。

```console
$ docker compose up --build
```

コンテナで確認する項目（非 root での実行、ヘルスチェックなど）は
[doc/verify-container.md](verify-container.md) にあります。

## 8. Worker を動かす（任意）

```console
$ cd worker
$ npm ci
$ npx wrangler dev
```

http://localhost:8787 で待ち受けます。Containers のローカル実行には Docker が必要で、
挙動に癖があります。まずは 7. のデモアプリ単体で確認するほうが確実です。
Cloudflare へのデプロイは [doc/demo.md](demo.md#cloudflare-へのデプロイ) を参照してください。

## Windows の場合

ここまでのコマンドは macOS・Linux のシェルを前提にしています。Windows（コマンドプロンプト・
PowerShell）では、次の点が違います。

**Ruby は RubyInstaller の「Ruby+Devkit」版を入れてください。** インストール後に `ridk install` で
MSYS2 を用意します。デモアプリが使う puma と nio4r は、インストール時に C 拡張をビルドするためです。

**CLI は `bundle exec ruby exe/gento` で起動します。** `bundle exec exe/gento` と打つと
`bundler: command not found: exe/gento` になり、`bundle install` しても直りません。
Windows は実行できるかどうかを拡張子で判断するので、Bundler が拡張子のない `exe/gento` を
コマンドとして見つけられないためです。`gem install` でインストールした場合は、RubyGems が
`gento.bat` を作るので、`gento` で直接起動できます。

そのほか、書き方が変わるところです。

| この文書での書き方 | Windows での書き方 |
| --- | --- |
| `bin/rspec` などの binstub | 拡張子がないので起動できません。`bundle exec rspec` がそのまま動くので、binstub は不要です |
| `(cd web && bundle install && bundle exec rspec)` | 1行ずつ実行します（`cd web` → `bundle install` → `bundle exec rspec` → `cd ..`）。コマンドプロンプトでは括弧の中の `cd` が戻らず、Windows PowerShell 5.1 は `&&` に対応していません |
| `PORT=9292 bundle exec puma …` | 先に、コマンドプロンプトなら `set PORT=9292`、PowerShell なら `$env:PORT = "9292"` を実行します |
| 行末の `\` で折り返したコマンド | 1行で書きます |
| `curl …` | Windows PowerShell 5.1 では `curl` が `Invoke-WebRequest` の別名なので、`curl.exe` と打ちます |

デモアプリの `bundle install` で、`web/Gemfile.lock` に Windows のプラットフォームが書き足される
ことがあります。その差分はコミットしなくて大丈夫です。

## つまずきやすいところ

**Windows で `bundler: command not found: exe/gento`**
`bundle exec ruby exe/gento` で起動してください（[Windows の場合](#windows-の場合)）。

**macOS・Linux で `bundler: command not found: rspec`（`puma` なども）**
gem の実行ファイルの置き場が `PATH` に入っていません。`bin/` の binstub を使うか、
`PATH="$(ruby -e 'print Gem.bindir'):$PATH"` を付けて実行してください。

**SlideShare だけ `ExtractionError`（bot challenge）になる**
接続元 IP の評価で弾かれています。gem 側の問題ではありません
（[doc/verification.md](verification.md#slideshare-のボット判定について)）。

**`RobotsDisallowedError` になる**
取得先の `robots.txt` が拒否しているか、`robots.txt` 自体を読めなかった（5xx・429・接続失敗）
ときに起きます。判定のルールは [doc/robots.md](robots.md) を参照してください。
