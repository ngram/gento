# RubyGems への公開手順

`gento` を RubyGems.org に公開するための手順です。
公開前に [doc/legal.md](legal.md) にも目を通してください。

## 現状

- **gem 名 `gento` は未使用です**（2026年10月に RubyGems API で確認済み。
  `gentou` も空いています）
- `gem build gento.gemspec` は警告なしで通り、24ファイルがパッケージされます
  （`lib/`、`exe/`、README、CHANGELOG、LICENSE。テストとフィクスチャは含みません）

## 事前チェック

```console
$ bundle exec rspec && bundle exec rubocop     # 151 examples / 0 offenses
$ gem build gento.gemspec                      # 警告が出ないこと
$ gem install ./gento-0.1.0.gem                # 手元で入るか
$ gento --version
```

パッケージの中身は必ず確認してください。`spec.files` の glob を間違えると、
不要なファイルが同梱されたり、逆に必要なファイルが欠けたりします。

```console
$ tar -xOf gento-0.1.0.gem data.tar.gz | tar -tzf -
```

## 方法A: 手元から push（最短）

初回はこちらが簡単です。

```console
$ gem signin                       # RubyGems.org のアカウントでサインイン
$ gem push gento-0.1.0.gem
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
自分が owner として登録されます。方法A で先に公開しておく必要はありません。

ワークフローは [`.github/workflows/release.yml`](../.github/workflows/release.yml) にあります。
`v*` のタグが push されると起動し、`rubygems/release-gem` が `rake release` を実行します。
タグはすでにあるので、`rake release` はタグ付けとブランチの push を飛ばし、
gem のビルドと push だけを行います。`id-token: write` を忘れると OIDC トークンが取れず失敗します。

gemspec の `rubygems_mfa_required` は、アカウントの API キーで push するとき（方法A）に
MFA を求めるものです。Trusted Publishing で発行されるキーには適用されないので、
この方法での公開は妨げません。

### pending trusted publisher を登録する

1. RubyGems.org にログインし、アカウントの **MFA を有効にしておきます**
2. ログインした状態で https://rubygems.org/profile/oidc/pending_trusted_publishers を開き、
   「Create」を押します（ログインしていないとサインイン画面へ転送されます）
3. 次のように入力して「Create Pending trusted publisher」を押します

   | 項目 | 値 |
   | --- | --- |
   | gem 名 | `gento` |
   | リポジトリのオーナー | `ngram` |
   | リポジトリ名 | `gento` |
   | ワークフローのファイル名 | `release.yml` |
   | Environment | 空欄 |

**pending trusted publisher は、作成から約12時間で失効します。** `release.yml` と
CHANGELOG を `main` に入れてから作成し、作成したらすぐにタグを push してください。
失効したら作り直せば済みます。初回の公開に成功して通常の trusted publisher に変われば、
以後は失効しません。

## リリースの流れ

`lib/gento/version.rb` と CHANGELOG.md を更新する PR を作り、`main` にマージします。
そのあと `main` の先頭にタグを打って push します。

```console
$ git switch main
$ git pull
$ git tag v0.1.0             # version.rb の VERSION と同じ番号にする
$ git push origin v0.1.0     # 方法B ならこれで公開まで走る
```

**タグ名は `v` + `VERSION` と一致させてください。** `rake release` は `v#{VERSION}` の
タグがあるかどうかでタグ付けを飛ばすかを決めるので、ずれていると自分でタグを打って
ブランチを push しようとします。

GitHub の Actions タブで Release ワークフローが成功したら、https://rubygems.org/gems/gento
で公開されたことと、Changelog などのリンクが開くことを確認します。

方法A の場合は、タグを push したうえで、手元から `gem push` します。

## 公開後に取り消したい場合

```console
$ gem yank gento -v 0.1.0
```

**yank しても同じバージョン番号で再公開はできません。** 番号を上げてください。
また、一度公開されたものは各種ミラーに残ると考えたほうが安全です。
