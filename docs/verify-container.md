# コンテナイメージの検証手順

`web/Dockerfile` をローカルの Docker でビルドして動作確認するための手順です。
一般的な Linux + Docker 環境を想定しています（`docker compose` が使える前提。
古い環境なら `docker-compose` に読み替えてください）。

手元に Docker のあるマシンがない場合は、GitHub Codespaces で同じことができます。
iPhone だけで完結する手順を [docs/codespaces.md](codespaces.md) にまとめてあります
（Cloudflare へのデプロイまで含む）。

所要時間は初回ビルドで 3〜5分程度です。

## 0. 前提の確認

```sh
docker --version          # 20.10 以降なら十分
docker compose version
docker info > /dev/null && echo "daemon OK"
```

## 1. リポジトリを取得

```sh
git clone https://github.com/ngram/gento.git
cd gento
```

## 2. ビルド

**ビルドコンテキストはリポジトリのルートです。** `web/` ではありません。
デモアプリが gem を相対パス（`path: ".."`）で参照しているため、
両方がコンテキストに入っている必要があります。

```sh
docker build -f web/Dockerfile -t gento-web .
```

期待する結果:

- `build` ステージで `bundle install` が通り、puma のネイティブ拡張がコンパイルされる
- `runtime` ステージが `ruby:3.3-slim` ベースで出来上がる
- 最終行が `naming to docker.io/library/gento-web`

イメージサイズを確認します。

```sh
docker images gento-web
```

## 3. 起動

```sh
docker run --rm -p 8080:8080 --name gento-web gento-web
```

`Puma starting` と `* Listening on http://0.0.0.0:8080` が出れば起動成功です。
以降は**別のターミナル**で確認します。

`docker compose up --build` でも同じことができます（`docker-compose.yml` 同梱）。

## 4. 確認すること

### 4-1. ヘルスチェック

Cloudflare Containers はこのエンドポイントで起動を判定します。

```sh
curl -s localhost:8080/healthz
# => {"status":"ok","version":"0.1.0"}
```

Docker 側のヘルスチェックが `healthy` になることも確認します（30秒ほどかかります）。

```sh
docker inspect --format '{{.State.Health.Status}}' gento-web
# => healthy
```

### 4-2. 非 root で動いていること

```sh
docker exec gento-web id
# => uid=1000(app) gid=1000(app) groups=1000(app)
```

`uid=0(root)` が返ってきたら `USER app` が効いていません。

### 4-3. gem が読み込まれていること

```sh
docker exec gento-web bundle exec ruby -e \
  'require "gento"; puts Gento::VERSION; puts Gento.providers.join(", ")'
# => 0.1.0
# => speaker_deck, slide_share, docswell, google_slides
```

### 4-4. 実際に取得できること

4サービスを一通り。ネットワークに出るので数秒かかります。

```sh
for u in \
  "https://speakerdeck.com/axbom/what-does-ai-have-to-do-with-human-rights" \
  "https://www.slideshare.net/slideshow/pr-strategy-deck/70491980" \
  "https://www.docswell.com/s/Akira_Ikeda/Z7N1RD-2026-07-24-JaSST26Hokkaido" \
  "https://docs.google.com/presentation/d/1MVF6nWVXKlFVjLMnUoCtjkQ8pJBh4knmBcv5kFJn_eY/mobilepresent"
do
  printf '%s -> ' "$(echo "$u" | cut -d/ -f3)"
  curl -sG --data-urlencode "url=$u" localhost:8080/api/decks \
    | ruby -rjson -e 'd=JSON.parse($stdin.read); puts "#{d["page_count"]} pages | #{d["title"]}"'
done
```

期待する結果（ページ数は元スライドが更新されれば変わります）:

```
speakerdeck.com -> 50 pages | What does AI have to do with Human Rights?
www.slideshare.net -> 11 pages | PR Strategy Deck
www.docswell.com -> 57 pages | AIとひとりで 働く 〜今後に向けた， わたしの現在地 と みんなの論点〜
docs.google.com -> 18 pages | AWSからCloudflareへ移して わかった「サーバを所有しない」こと
```

### 4-5. HTML 画面

ブラウザで開いて、フォームにスライド URL を入れるとサムネイルが並びます。

```sh
xdg-open "http://localhost:8080/" 2>/dev/null || echo "http://localhost:8080/"
```

### 4-6. エラー経路

```sh
curl -s -o /dev/null -w "%{http_code}\n" "localhost:8080/api/decks"                       # 400
curl -s -o /dev/null -w "%{http_code}\n" "localhost:8080/api/decks?url=https://example.com/x"  # 422
curl -s -o /dev/null -w "%{http_code}\n" "localhost:8080/nope"                            # 404
```

### 4-7. キャッシュが効いていること

同じ URL を2回投げると、2回目は目に見えて速くなります。

```sh
U="https://www.docswell.com/s/Akira_Ikeda/Z7N1RD-2026-07-24-JaSST26Hokkaido"
time curl -sG --data-urlencode "url=$U" localhost:8080/api/decks > /dev/null
time curl -sG --data-urlencode "url=$U" localhost:8080/api/decks > /dev/null
```

## 5. 後始末

```sh
docker stop gento-web          # docker run を Ctrl-C でも可
docker rmi gento-web
```

## つまずきやすいところ

**`failed to compute cache key: "/web/Gemfile.lock" not found`**
`web/` をビルドコンテキストにしています。リポジトリのルートで
`-f web/Dockerfile ... .` の形で実行してください。

**`Your bundle is locked to ...` / `frozen mode`**
`web/Gemfile.lock` が `web/Gemfile` と食い違っています。
`cd web && bundle install` でロックを更新してコミットし直してください。

**`bundle install` がネットワークで失敗する**
プロキシ環境なら `--build-arg` ではなくビルド時の環境変数が必要です。

```sh
docker build -f web/Dockerfile \
  --build-arg http_proxy="$http_proxy" --build-arg https_proxy="$https_proxy" \
  -t gento-web .
```

なお gem 自体は `HTTPS_PROXY` を読むので、実行時のプロキシは
`docker run -e HTTPS_PROXY=... ` を渡すだけで通ります。

**4-4 で SlideShare だけ失敗する**
`bot challenge` を含むエラーが返っていれば、SlideShare 側のボット判定に
当たっています。判定は接続元 IP の評価で決まるため、データセンターの IP からは
恒常的に弾かれます。仕様どおりの挙動です
（[docs/verification.md](verification.md#slideshare-のボット判定について)）。

## Cloudflare へのデプロイまで確認する場合

イメージが問題なければ、そのまま Cloudflare 側の検証に進めます。
Docker が動く環境なら `--dry-run` でコンテナのビルドまで含めて検証できます。

```sh
cd worker
npm ci
npx wrangler deploy --dry-run          # ビルドまで通ることの確認（デプロイはしない）
npx wrangler deploy                    # 実デプロイ（Workers Paid プランが必要）
```
