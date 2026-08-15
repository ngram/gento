# RubyGems への公開手順

`slidescraper` を RubyGems.org に公開するための手順です。
公開前に [docs/legal.md](legal.md) にも目を通してください。

## 現状

- **gem 名 `slidescraper` は未使用です**（RubyGems API で確認済み。`slide_scraper` /
  `slidescrape` も空いています）
- `gem build slidescraper.gemspec` は警告なしで通り、22ファイルがパッケージされます
  （`lib/`、`exe/`、README、CHANGELOG、LICENSE。テストとフィクスチャは含みません）

## 事前チェック

```console
$ bundle exec rspec && bundle exec rubocop     # 102 examples / 0 offenses
$ gem build slidescraper.gemspec               # 警告が出ないこと
$ gem install ./slidescraper-0.1.0.gem         # 手元で入るか
$ slidescraper --version
```

パッケージの中身は必ず確認してください。`spec.files` の glob を間違えると、
不要なファイルが同梱されたり、逆に必要なファイルが欠けたりします。

```console
$ tar -xOf slidescraper-0.1.0.gem data.tar.gz | tar -tzf -
```

## 方法A: 手元から push（最短）

初回はこちらが簡単です。

```console
$ gem signin                       # RubyGems.org のアカウントでサインイン
$ gem push slidescraper-0.1.0.gem
```

- アカウントは https://rubygems.org/sign_up で作成します
- **MFA を有効にしてください。** gemspec に
  `spec.metadata["rubygems_mfa_required"] = "true"` を入れてあるので、
  以後この gem の操作には MFA が要求されます
- 認証情報は `~/.gem/credentials` に保存されます（`chmod 0600`）

## 方法B: Trusted Publishing（GitHub Actions から、推奨）

API キーを一切保存せずに、OIDC で GitHub Actions から公開する方式です。
長期有効なトークンをリポジトリのシークレットに置かずに済みます。

**まだ存在しない gem でも設定できます。** RubyGems.org に「pending trusted publisher」
として先に登録しておくと、初回 push が成功した時点で通常の trusted publisher に変わり、
自分が owner として登録されます。

1. https://rubygems.org/profile/oidc/pending_trusted_publishers/new を開く
2. gem 名、リポジトリのオーナー（`ngram`）、リポジトリ名（`slidescraper`）、
   ワークフローのファイル名（`release.yml`）を入力。GitHub Environment は任意
3. 下記のワークフローを `.github/workflows/release.yml` に置く

```yaml
name: Release

on:
  push:
    tags: ["v*"]

jobs:
  push:
    runs-on: ubuntu-latest
    permissions:
      id-token: write   # trusted publishing に必須
      contents: write   # `rake release` がタグを打つのに必要
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: "3.3"
          bundler-cache: true
      - uses: rubygems/release-gem@v1
```

`id-token: write` を忘れると OIDC トークンが取れず失敗します。

## リリースの流れ

```console
$ # lib/slidescraper/version.rb を編集
$ # CHANGELOG.md の Unreleased を確定させる
$ git commit -am "Release v0.1.0"
$ git tag v0.1.0
$ git push origin main --tags        # 方法B ならこれで公開まで走る
```

## 公開後に取り消したい場合

```console
$ gem yank slidescraper -v 0.1.0
```

**yank しても同じバージョン番号で再公開はできません。** 番号を上げてください。
また、一度公開されたものは各種ミラーに残ると考えたほうが安全です。
