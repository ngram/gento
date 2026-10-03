# GitHub Codespaces で検証する（iPhone Safari だけで完結）

コンテナビルドと Cloudflare デプロイを、手元に Docker のあるマシンがなくても試すための手順です。
iPhone の Safari だけで完結します。

`.devcontainer/` はこのリポジトリに含まれているので、**GitHub Web 上でファイルを作る作業は不要です**。
Codespace を起動すればそのまま使えます。

前提として、このドキュメントは `claude/slide-scraping-gem-sf023s` ブランチを対象にしています。

## 0. Codespace を起動する

Safari で `github.com/codespaces/new` を開く → リポジトリと**ブランチ**を選ぶ → Create。

初回は docker-in-docker のセットアップと3つの依存関係インストールで **5〜8分**かかります。
`postCreateCommand` が終わるまでターミナルは使えないので、待ってください。

マシンタイプは **2-core のまま**にしておきます。`.devcontainer/devcontainer.json` で
`hostRequirements.cpus` を 2 に指定してあるので、既定でそうなります。
無料枠（個人アカウントで月 120 core-hours）の消費が 4-core の半分で済みます。

## 1. iPhone で操作しやすくする

- 起動したら共有ボタン → **ホーム画面に追加**。Safari のアドレスバーが消えて縦幅が稼げます
- **横向き必須**です
- ターミナルは `Ctrl+@` 系のショートカットが押せないので、左上の **☰ → Terminal → New Terminal**
- Escape キーがないので、`vim` などのモーダルエディタは開かないこと

## 2. ベースラインを確認する

3つのスイートがあります。合計 **128件**です。

```sh
bundle exec rspec                          # gem: 151 examples
(cd web && bundle exec rspec)              # デモアプリ: 27 examples
(cd worker && npm test && npm run typecheck)   # Worker: 15 tests
```

gem のテストはソケットを一切開かない設計なので、Codespaces のネットワーク環境に関係なく通ります。

## 3. コンテナイメージのビルド（唯一の未検証項目）

```sh
docker info      # デーモンの生存確認
```

これが通れば [docs/verify-container.md](verify-container.md) の手順がそのまま使えます。
**ビルドコンテキストはリポジトリのルート**である点にだけ注意してください
（デモアプリが gem を `path: ".."` で参照しているため、`web/` を指定すると失敗します）。

```sh
docker build -f web/Dockerfile -t slidescraper-web .
docker run --rm -d -p 8080:8080 --name slidescraper-web slidescraper-web
```

確認項目は `verify-container.md` に7つ並べてあります。最低限これだけでも：

```sh
curl -s localhost:8080/healthz
docker exec slidescraper-web id            # uid=1000(app) であること
```

## 4. デモを iPhone の画面で見る

コンテナを起動した状態で **PORTS** タブを開くと 8080 が出ています。URL をタップすれば
Safari で開きます。フォームに Speaker Deck や Docswell の URL を入れて画像一覧が出れば
end-to-end 確認は完了です。

コンテナを使わず直接起動することもできます（ポートは同じ 8080 です）。

```sh
cd web && bundle exec puma -C config/puma.rb config.ru
```

> `ruby app.rb` では起動しません。デモは `Sinatra::Base` のサブクラスなので、
> `config.ru` 経由で rack サーバーに載せる必要があります。

## 5. Cloudflare にデプロイする

### 5-1. 認証は API トークンで行う（`wrangler login` は使えません）

`wrangler login` は OAuth のコールバックを `http://localhost:8976` で受けます。
このリダイレクトは**ブラウザが動いている端末**（つまり iPhone）の localhost に向かうので、
Codespace には届きません。iPhone からは成立しない経路です。

代わりに API トークンを使います。Safari で
`dash.cloudflare.com/profile/api-tokens` → **Create Token** →
テンプレート **Edit Cloudflare Workers** を選択 → 対象アカウントを指定して作成。

アカウント ID は Cloudflare ダッシュボードのアカウントホーム、または URL の
`dash.cloudflare.com/<ここがアカウントID>` から取れます。

Codespace のターミナルで環境変数に入れます。**シェル履歴に残さない**よう `read -s` を使います。

```sh
read -rs CLOUDFLARE_API_TOKEN && export CLOUDFLARE_API_TOKEN
read -r CLOUDFLARE_ACCOUNT_ID && export CLOUDFLARE_ACCOUNT_ID
```

トークンを繰り返し使うなら、Codespaces のシークレットに入れるほうが安全で楽です。
`github.com/settings/codespaces` → **Codespaces secrets** → 上記2つの名前で登録し、
このリポジトリに紐付けると、次回以降の Codespace に環境変数として自動で入ります。

> リポジトリにトークンを書いたファイルを作らないでください。`.dev.vars` は
> `.gitignore` 済みですが、そもそも置かないのが確実です。

### 5-2. 疎通確認

```sh
cd worker
npx wrangler whoami
```

アカウント名が表示されればトークンは有効です。

### 5-3. まず dry-run

デプロイせずに、設定とコンテナイメージのビルドまでを検証します。
Codespace には Docker があるので、**ここで初めてコンテナのビルドまで含めた検証が通ります**
（これまでの環境では Docker デーモンがなく、この段階で止まっていました）。

```sh
npx wrangler deploy --dry-run
```

バインディング一覧とコンテナが解決されれば設定は正しいです。

### 5-4. デプロイ

**Containers の利用には Workers Paid プラン（$5/月）が必要です。** 無料プランのままだと
ここで失敗します。課金が発生する操作なので、意図を確認してから実行してください。

```sh
npx wrangler deploy
```

初回はコンテナイメージのビルドと push があるため数分かかります。完了すると
`https://slidescraper.<subdomain>.workers.dev` の URL が表示されるので、
iPhone の Safari でそのまま開けます。

```sh
curl -s https://slidescraper.<subdomain>.workers.dev/healthz
```

### 5-5. ログを見る

```sh
npx wrangler tail
```

### 5-6. 後始末（課金を止める）

デプロイしたまま放置するとコンテナのスリープまでの稼働時間で課金され続けます。
試すだけなら削除しておきます。

```sh
npx wrangler delete
```

## 6. ローカルで Worker を動かす（任意）

```sh
cd worker && npx wrangler dev
```

PORTS タブに 8787 が出ます。ただし Containers のローカルエミュレーションは癖があるので、
**まずは 3. の素の `docker run` で疎通を取るほうが確実**です。

## 7. iPhone でのタイピングを回避する

長文のコードを iPhone で打つのは現実的ではありません。**Codespaces は「Docker が動く実行環境」として使い、
編集は Claude Code に委ねる**割り切りをおすすめします。`.devcontainer/setup.sh` で
インストール済みです。

```sh
claude
```

OAuth ログイン後は、指示だけで作業できます。

> docs/verify-container.md の手順どおりにコンテナをビルドして起動し、4サービス分の URL で疎通確認して結果を報告して

同じ要領で、新しく見つかった不具合や対応サービスの追加もそのまま任せられます。

## 8. 終わったら止める

`github.com/codespaces` → 該当 Codespace の「…」→ **Stop codespace**。
既定では30分で自動停止しますが、明示的に止めたほうが確実です。

ストレージは停止中も無料枠（15GB-month）を消費します。検証が終わったら **Delete** まで。
このリポジトリの Codespace はイメージのビルド成果物を含めて数 GB になります。

## つまずきやすいところ

**コンテナ作成が `Failed to fetch the latest artifacts for docker-compose` で失敗する**

```
(*) Installing docker-compose 2.40.3...
curl: (56) Connection died, tried 5 times before giving up
ERROR: Feature "Docker (Docker-in-Docker)" failed to install!
```

moby 本体の apt インストールは成功した後、feature が**さらに** standalone の
`docker-compose` バイナリを GitHub releases から取りに行って失敗しています。
Codespaces のビルド環境からこのダウンロードが通らないことがあります。

このリポジトリの `devcontainer.json` は `"dockerDashComposeVersion": "none"` を
指定してこの二重インストールを止めています。apt の `moby-compose` パッケージが
`docker compose`（スペース区切りの v2 プラグイン）を提供するので、これで不足はありません。
ハイフン付きの `docker-compose` コマンドだけが入らなくなります。

**コンテナ作成が `moby-cli ... not available in that distribution` で失敗する**

作成ログにこう出ている場合:

```
(!) The 'moby' option is not supported on debian 'trixie' because
    'moby-cli' and related system packages are not available in that distribution.
ERROR: Feature "Docker (Docker-in-Docker)" failed to install!
```

ベースイメージの Debian が trixie に上がり、docker-in-docker feature が既定で入れる
moby パッケージが存在しないためです。コンテナ作成が失敗し、Codespaces は黙って
リカバリーコンテナ（`base:alpine`）に切り替えます。**その結果が下の「3つとも見つからない」です。**

このリポジトリの `devcontainer.json` はベースイメージを `3.3-bookworm` に固定して
これを回避しています。**ディストロの接尾辞を外さないでください。**
浮動タグ（`:3.3`）に戻すと、Debian が次に上がったときに同じ壊れ方をします。

もう一つの回避策は feature 側で moby を無効にすることです（Docker CE が入ります）。

```jsonc
"ghcr.io/devcontainers/features/docker-in-docker:2": { "moby": false }
```

**`ruby` / `node` / `bundle` が「3つとも」見つからない**

`.devcontainer/setup.sh` の冒頭で3つとも `MISSING` と出る場合、devcontainer が
適用されていません。ruby イメージと node feature が効いていれば、少なくとも
ruby と node は存在するはずだからです。原因は次のどちらかです。

1. devcontainer を追加する前に作った Codespace を使っている
2. コンテナのビルドに失敗し、Codespaces が**リカバリーモード**で起動した

**ファイルを `git pull` してもコンテナは作り直されません。** リビルドが必要です。

まず何が起きたかを確認します。コマンドパレット（iPhone では左上の ☰ → View →
Command Palette）で:

```
Codespaces: View Creation Log
```

`devcontainer` のビルドが失敗していれば、その理由がここに出ます。

続いてリビルドします。**ターミナルから実行するのが一番確実です** — iOS の Safari では
メニューやコマンドパレットのタッチが効かないことがあるためです。

```sh
gh codespace rebuild --full -c "$CODESPACE_NAME"
```

`--full` はキャッシュした Docker イメージも捨てて最初からやり直します。
`$CODESPACE_NAME` は Codespace 内で自動的に設定済みで、`gh` も認証済みです。
5〜8分かかり、その間セッションは切断されます。完了したらブラウザを再読み込みしてください。

UI から実行する場合はコマンドパレットで `Codespaces: Full Rebuild Container` です。
コマンドパレットはメニュー以外からも開けます。

- 外付けキーボードがあれば `F1` または `Cmd+Shift+P`
- 画面上部中央の**コマンドセンター**（Codespace 名が表示されている横長のボックス）を
  タップし、先頭に `>` を入力する

それでも駄目なら、Codespace を作り直すのが確実です。
`github.com/codespaces` → 該当の「…」→ **Delete** してから新規作成してください。

**`bundle: command not found` になる（ruby はある）**

まず何が起きているか確認します。

```sh
which ruby; ruby -v
which bundle
ls .ruby-version 2>/dev/null && cat .ruby-version
```

`ruby` はあるのに `bundle` がない、あるいは `ruby -v` 自体がエラーになる場合、
**`.ruby-version` がイメージに入っていないパッチバージョンを指している**のが典型です。
バージョンマネージャ（rvm / rbenv）が有効化に失敗し、gem の実行ファイルが
PATH に載らないため、`bundle` を含めて何も見つからなくなります。

このリポジトリは `.ruby-version` を置かない方針にしました（gemspec が `>= 3.1` を
宣言していて、CI は明示的なマトリクスでバージョンを指定するため、重複した固定は不要です）。
古い Codespace に残っている場合は削除してください。

```sh
rm -f .ruby-version
```

削除したら**新しいターミナルを開いて**（バージョンマネージャのフックはシェル起動時に
走るため、既存のターミナルでは直りません）、セットアップをやり直します。

```sh
bash .devcontainer/setup.sh
```

インストール済みのバージョンを確認したい場合:

```sh
rbenv versions 2>/dev/null || rvm list 2>/dev/null || gem env | head -20
```

**`postCreateCommand` が失敗して依存が入っていない**
`bash .devcontainer/setup.sh` を手で再実行してください。冒頭で ruby / bundler / node の
所在を表示し、`bundle` が見つからない場合は原因の候補を出して止まります。

**`docker build` が `web/Gemfile.lock not found` で落ちる**
`web/` をビルドコンテキストにしています。リポジトリのルートで `-f web/Dockerfile ... .` の形で。

**`wrangler deploy` が権限エラーになる**
`Edit Cloudflare Workers` テンプレートのトークンでも、Containers には追加の権限が要る場合があります。
エラーメッセージが不足しているスコープを名指しするので、それに合わせてトークンを作り直してください。

**SlideShare だけ `bot challenge` で失敗する**

まず、コンテナ固有の問題かネットワーク全体かを切り分けます。Codespace のターミナルで:

```sh
curl -sS -A "slidescraper/0.1.0" \
  "https://www.slideshare.net/slideshow/ansiblenetwork201808/108457145" \
  | grep -c "Client Challenge"
```

`1` が返れば、gem ではなく**この Codespace の出口 IP がボット判定を受けています**。
SlideShare の保護はリクエストの中身より接続元の評価で判断するため、
データセンターの IP（Codespaces は Azure）は恒常的に弾かれることがあります。
ヘッダを変えても通らないのが普通です。

`0` が返るのに gem だけ失敗する場合は User-Agent の可能性があります。
デモアプリは環境変数で差し替えられるので、再ビルドせずに試せます。

```sh
docker run --rm -p 8080:8080 \
  -e SLIDESCRAPER_USER_AGENT="Mozilla/5.0 (compatible; slidescraper/0.1.0)" \
  slidescraper-web
```

どちらでも通らない場合、残る手段は JavaScript を実行できる `Slidescraper::Fetcher` を
差し込むことです（gem 本体は無改造で載ります）。他の3サービスは影響を受けません。
