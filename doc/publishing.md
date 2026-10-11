# RubyGems への公開手順

`gento` を RubyGems.org に公開する手順です。公開は GitHub Actions の Trusted Publishing で行います。
公開前に [doc/legal.md](legal.md) にも目を通してください。

## 現状

- RubyGems.org に 0.1.1 を公開済みです（[rubygems.org/gems/gento](https://rubygems.org/gems/gento)、2026年10月5日）。
  0.1.0 は yank しました
- trusted publisher は登録済みです。通常のリリースでは、[リリースの流れ](#リリースの流れ毎回) だけを行います
- `gem build gento.gemspec` は警告なしで通り、24ファイルがパッケージされます
  （`lib/`、`exe/`、README、CHANGELOG、LICENSE。テストとフィクスチャは含みません）

## Trusted Publishing の仕組み

OIDC を使って GitHub Actions から公開する方式です。
長期有効な API キーを、手元にもリポジトリのシークレットにも置かずに済みます。

ワークフローは [`.github/workflows/release.yml`](../.github/workflows/release.yml) にあります。
`v*` のタグが push されると起動し、`rubygems/release-gem` が `rake release` を実行します。
タグはすでにあるので、`rake release` はタグ付けとブランチの push を省略し、
gem のビルドと push だけを行います。`id-token: write` を忘れると OIDC トークンが取れず失敗します。

RubyGems.org は、登録したリポジトリとワークフローのファイル名（`release.yml`）からの push だけを
受け付けます。ファイル名を変えると、RubyGems.org 側の登録を合わせて直すまで公開できません。
登録内容は https://rubygems.org/gems/gento/trusted_publishers で確認・変更できます。

gemspec の `rubygems_mfa_required` は、アカウントの API キーを使う操作（手元からの `gem push` や
`gem yank` など）に MFA を求める設定です。Trusted Publishing で発行されるキーには適用されないので、
この方式での公開は妨げません。

## 初回のみ: pending trusted publisher を登録する

RubyGems.org にまだ存在しない gem を、Trusted Publishing で初めて公開するときだけの手順です。
gento は公開済みなので、今後は使いません。

RubyGems.org に「pending trusted publisher」として先に登録しておくと、初回の push が成功した時点で
通常の trusted publisher に変わり、自分が owner として登録されます。

1. RubyGems.org にログインし、アカウントの MFA を有効にしておきます
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
失効したら作り直せば済みます。通常の trusted publisher に変われば、以後は失効しません。

## リリースの流れ（毎回）

ファイル名やタグに出てくる `0.1.1` は、`lib/gento/version.rb` の `VERSION` に読み替えてください。

### 1. バージョンを上げる PR をマージする

`lib/gento/version.rb` と CHANGELOG.md を更新する PR を作り、次のチェックを通してから
`main` にマージします。

```console
$ bundle exec rspec && bundle exec rubocop     # 151 examples / 0 offenses
$ gem build gento.gemspec                      # 警告が出ないこと
$ gem install --local gento                    # 手元で入るか
$ gento --version
```

パッケージの中身は必ず確認してください。`spec.files` の glob を間違えると、
不要なファイルが同梱されたり、逆に必要なファイルが欠けたりします。

```console
$ tar -xOf gento-0.1.1.gem data.tar.gz | tar -tzf -
```

### 2. タグを push する

`main` の先頭にタグを打って push すると、Release ワークフローが gem を公開します。

```console
$ git switch main
$ git pull
$ git tag v0.1.1             # version.rb の VERSION と同じ番号にする
$ git push origin v0.1.1
```

**タグ名は `v` + `VERSION` と一致させてください。** `rake release` は `v#{VERSION}` の
タグがあるかどうかでタグ付けを省略するかを決めます。ずれていると、`rake release` が
自分でタグを打ち、ブランチを push しようとします。

### 3. 公開を確認する

GitHub の Actions タブで Release ワークフローが成功したら、https://rubygems.org/gems/gento
で公開されたことと、Changelog などのリンクが開くことを確認します。

RubyGems.org 側の登録など、リポジトリの外にある原因でワークフローが失敗した場合は、
原因を直してから Actions の画面で失敗したジョブを再実行します。タグを打ち直す必要はありません。

## 公開後に取り消したい場合

yank は Trusted Publishing ではできないので、手元からアカウントの認証情報で実行します。
`gem signin` の認証情報は `~/.gem/credentials` に保存されます（`chmod 0600`）。

```console
$ gem signin                    # サインイン済みなら不要
$ gem yank gento -v 0.1.1       # rubygems_mfa_required により MFA のコードを求められる
```

**yank しても同じバージョン番号で再公開はできません。** 番号を上げてください。
また、一度公開されたものは各種ミラーに残ると考えたほうが安全です。
yank したバージョンは、CHANGELOG の該当する見出しにその旨を書いておきます。
