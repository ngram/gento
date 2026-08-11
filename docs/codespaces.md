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
bundle exec rspec                          # gem: 97 examples
(cd web && bundle exec rspec)              # デモアプリ: 16 examples
(cd worker && npm test && npm run typecheck)   # Worker: 15 tests
```

gem のテストはソケットを一切開かない設計なので、Codespaces のネットワーク環境に関係なく通ります。

## 3. コンテナイメージのビルド（未検証項目のひとつ）

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

未検証のもう1点、Google スライドの `/d/e/<id>/` 形式（「ファイル → 共有 → ウェブに公開」で
作った URL）も、そのまま投げればアダプタの修正からテスト追加まで任せられます。

## 8. 終わったら止める

`github.com/codespaces` → 該当 Codespace の「…」→ **Stop codespace**。
既定では30分で自動停止しますが、明示的に止めたほうが確実です。

ストレージは停止中も無料枠（15GB-month）を消費します。検証が終わったら **Delete** まで。
このリポジトリの Codespace はイメージのビルド成果物を含めて数 GB になります。

## つまずきやすいところ

**`postCreateCommand` が失敗して依存が入っていない**
ターミナルで `bash .devcontainer/setup.sh` を手で再実行してください。

**`docker build` が `web/Gemfile.lock not found` で落ちる**
`web/` をビルドコンテキストにしています。リポジトリのルートで `-f web/Dockerfile ... .` の形で。

**`wrangler deploy` が権限エラーになる**
`Edit Cloudflare Workers` テンプレートのトークンでも、Containers には追加の権限が要る場合があります。
エラーメッセージが不足しているスコープを名指しするので、それに合わせてトークンを作り直してください。

**SlideShare だけ疎通確認に失敗する**
エラーに `bot challenge` が含まれていれば仕様どおりの挙動です。時間をおいて再実行してください。
