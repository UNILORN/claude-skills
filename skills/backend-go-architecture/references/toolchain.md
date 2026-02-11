# ツールチェーン

Buf、sqlc、Atlas、golangci-lint、Dockerfile の設定と使用方法。

---

## Proto コード生成 (Buf)

### 設定 (`buf.yaml`)

```yaml
version: v2
modules:
  - path: proto
lint:
  use:
    - STANDARD        # 標準 lint ルール (命名規約など)
breaking:
  use:
    - FILE            # ファイルレベルの後方互換性チェック
```

### Proto ファイル構成

```
proto/
└── {feature}/v1/
    └── {feature}.proto
```

### Proto テンプレート

```protobuf
syntax = "proto3";
package {feature}.v1;

option go_package = "github.com/example/go-react-app/gen/{feature}/v1;{feature}v1";

message {Feature} {
  string id = 1;
  // フィールド定義
}

message Create{Feature}Request {
  // 入力フィールド (id を除く)
}

message Create{Feature}Response {
  {Feature} {feature} = 1;
}

message Get{Feature}Request {
  string id = 1;
}

message Get{Feature}Response {
  {Feature} {feature} = 1;
}

service {Feature}Service {
  rpc Create{Feature}(Create{Feature}Request) returns (Create{Feature}Response);
  rpc Get{Feature}(Get{Feature}Request) returns (Get{Feature}Response);
}
```

**規約:**
- `go_package` は `gen/{feature}/v1;{feature}v1` (セミコロン後がパッケージエイリアス)
- パッケージ名: `{feature}.v1`
- メッセージ命名: `{Verb}{Feature}Request` / `{Verb}{Feature}Response`
- レスポンスにはエンティティをラップ

### 生成コマンド

```bash
pnpm buf:generate    # Go + TypeScript 両方を生成
```

生成先:
- Go: `packages/backend-go/gen/{feature}/v1/`
- TypeScript: `packages/frontend-react/gen/{feature}/v1/`

---

## SQL コード生成 (sqlc)

### 生成コマンド

```bash
pnpm sqlc:generate
```

### クエリ記法

```sql
-- name: {MethodName} :{return_type}
-- :one  → 1行取得 (エラー: pgx.ErrNoRows)
-- :many → 複数行取得 (空なら [])
-- :exec → 実行のみ (戻り値なし)
```

### 新 Feature 追加手順

1. `internal/{feature}/infra/queries.sql` にクエリを定義
2. `sqlc.yaml` にエントリを追加:

```yaml
  - engine: "postgresql"
    queries: "internal/{feature}/infra/queries.sql"
    schema: "db/schema.sql"
    gen:
      go:
        package: "sqlcgen"
        out: "internal/{feature}/infra/sqlcgen"
        sql_package: "pgx/v5"
        emit_json_tags: true
        emit_prepared_queries: false
        emit_interface: false
        emit_exact_table_names: false
        emit_empty_slices: true
```

3. `pnpm sqlc:generate` を実行

---

## スキーママイグレーション (Atlas)

### 設定 (`atlas.hcl`)

```hcl
variable "db_url" {
  type    = string
  default = getenv("DATABASE_URL")
}

env "local" {
  src = "file://db/schema.sql"
  url = var.db_url
  dev = "docker://postgres/16/dev?search_path=public"
  migration {
    dir = "file://db/migrations"
  }
}

env "test" {
  src = "file://db/schema.sql"
  url = "postgres://test:test@localhost:5433/test?sslmode=disable"
  dev = "docker://postgres/16/dev?search_path=public"
}
```

### コマンド

```bash
pnpm atlas:diff     # schema.sql の差分からマイグレーションを生成
pnpm atlas:apply    # マイグレーションを DB に適用
```

### ワークフロー

1. `db/schema.sql` を編集 (テーブル追加、カラム変更など)
2. `pnpm atlas:diff` — Docker で一時的な Postgres を起動して差分を計算
3. `db/migrations/` に生成された SQL を確認
4. `pnpm atlas:apply` — 対象 DB にマイグレーションを適用

---

## コード品質 (golangci-lint)

### 設定 (`.golangci.yml`)

**有効 Linter:**

| カテゴリ | Linter | 目的 |
|---------|--------|------|
| デフォルト | errcheck, gosimple, govet, ineffassign, staticcheck, unused | 基本的な品質チェック |
| フォーマット | gofmt, goimports | コードフォーマット |
| セキュリティ | gosec | セキュリティ脆弱性 |
| スタイル | gocritic, revive, misspell | コーディングスタイル |
| エラー | errorlint, nilerr, bodyclose | エラーハンドリング |
| その他 | unconvert, unparam | 不要な変換、未使用パラメータ |

**Import 順序** (`goimports`):

```go
import (
    // 1. 標準ライブラリ
    "context"
    "log/slog"

    // 2. 外部ライブラリ
    "connectrpc.com/connect"
    "github.com/google/uuid"

    // 3. 内部パッケージ (github.com/example/go-react-app)
    "github.com/example/go-react-app/internal/..."
)
```

**除外ルール:**
- `gen/` — 生成コードは lint 対象外
- `sqlcgen/` — 生成コードは lint 対象外
- `_test.go` — `gosec`, `unparam` を除外

### 実行

```bash
cd packages/backend-go && golangci-lint run ./...
```

---

## Docker ビルド (`Dockerfile`)

### Multi-stage Build

```dockerfile
# Build stage
FROM golang:1.25.7-alpine AS builder
WORKDIR /app
RUN apk add --no-cache git ca-certificates tzdata
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -ldflags="-w -s" \
    -o /app/server \
    ./cmd/app

# Production stage
FROM gcr.io/distroless/static:nonroot
COPY --from=builder /app/server /server
COPY --from=builder /usr/share/zoneinfo /usr/share/zoneinfo
USER nonroot:nonroot
EXPOSE 8080
ENTRYPOINT ["/server"]
```

**ビルド最適化:**
- `CGO_ENABLED=0` — 静的バイナリ (Distroless で動作可能)
- `-ldflags="-w -s"` — デバッグ情報とシンボルテーブルを削除 (バイナリサイズ縮小)
- `go mod download` を先に実行 (Docker キャッシュ活用)

**セキュリティ:**
- Distroless イメージ (シェルもパッケージマネージャーもない最小イメージ)
- `nonroot` ユーザーで実行
- タイムゾーンデータを明示的にコピー (time 操作用)

---

## 依存関係 (`go.mod`)

```
go 1.24.3

// 直接依存
connectrpc.com/connect v1.19.1        // ConnectRPC フレームワーク
connectrpc.com/cors v0.1.0            // ConnectRPC 用 CORS ヘルパー
connectrpc.com/grpchealth v1.4.0      // gRPC ヘルスチェック
github.com/coreos/go-oidc/v3 v3.17.0  // OIDC クライアント
github.com/google/uuid v1.6.0         // UUID 生成
github.com/jackc/pgx/v5 v5.8.0        // PostgreSQL ドライバー
github.com/rs/cors v1.11.1            // CORS ミドルウェア
golang.org/x/oauth2 v0.35.0           // OAuth2 クライアント
google.golang.org/protobuf v1.36.11   // Protobuf ランタイム

// 間接依存 (主要)
github.com/joho/godotenv v1.5.1       // .env ファイル読み込み
```

---

## コマンド一覧

| コマンド | 説明 |
|---------|------|
| `pnpm buf:generate` | Proto → Go + TypeScript 生成 |
| `pnpm sqlc:generate` | SQL → Go 型安全コード生成 |
| `pnpm atlas:diff` | スキーマ差分からマイグレーション生成 |
| `pnpm atlas:apply` | マイグレーション適用 |
| `pnpm dev:backend` | Go サーバー起動 (localhost:8080) |
| `pnpm dev` | Backend + Frontend 同時起動 |
