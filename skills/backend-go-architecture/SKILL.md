---
name: backend-go-architecture
description: Go バックエンドの実装リファレンス。Package by Feature + Clean Architecture の実際のコード構成、ConnectRPC ハンドラー、sqlc による型安全 DB アクセス、OIDC 認証、DI パターン、ミドルウェア、エラーハンドリングを網羅。「バックエンド」「Go」「handler」「usecase」「domain」「infra」「sqlc」「ConnectRPC」「認証」「ミドルウェア」「DI」「main.go」「トランザクション」「repository」「store」で発動。
---

# Backend Go Architecture Reference

現在のバックエンド Go ソースコードの実装パターンを完全に文書化したスキル。
新機能追加・バグ修正・リファクタリング時にこのスキルを参照すること。

## Tech Stack

| カテゴリ | 技術 | バージョン |
|---------|------|-----------|
| Language | Go | 1.24.3 |
| API Framework | ConnectRPC | v1.19.1 |
| Database Driver | pgx/v5 | v5.8.0 |
| SQL Codegen | sqlc | v2 |
| Schema Migration | Atlas | - |
| Proto Codegen | Buf | v2 |
| Auth | go-oidc/v3 + oauth2 | v3.17.0 |
| CORS | rs/cors + connectrpc/cors | v1.11.1 |
| UUID | google/uuid | v1.6.0 |
| Logging | log/slog (stdlib) | - |
| Linting | golangci-lint | 20+ linters |
| Container | Distroless (nonroot) | - |

## Directory Structure (実際のコード)

```
packages/backend-go/
├── cmd/app/
│   └── main.go                    # エントリーポイント、DI、サーバー起動
├── db/
│   ├── schema.sql                 # DB スキーマ (Single Source of Truth)
│   └── migrations/                # Atlas 生成マイグレーション
├── gen/                           # Proto 生成コード (gitignore)
│   └── {feature}/v1/
│       ├── {feature}.pb.go
│       └── {feature}v1connect/
│           └── {feature}.connect.go
├── internal/
│   ├── config/
│   │   └── config.go              # 環境変数ベースの設定管理
│   ├── database/
│   │   └── tx.go                  # トランザクション Context ヘルパー
│   ├── domain/
│   │   └── user.go                # 共有ドメインエンティティ
│   └── {feature}/                 # Package by Feature
│       ├── domain/                # Repository IF, エラー定義
│       ├── usecase/               # ビジネスロジック
│       ├── handler/               # ConnectRPC / HTTP ハンドラー
│       ├── middleware/            # (auth のみ) HTTP ミドルウェア
│       └── infra/                 # Repository 実装
│           ├── queries.sql        # sqlc クエリ定義
│           ├── sqlcgen/           # sqlc 生成コード (gitignore)
│           ├── store.go           # PostgreSQL 実装
│           └── memory_store.go    # インメモリ実装 (dev/test)
├── proto/
│   └── {feature}/v1/
│       └── {feature}.proto        # Proto サービス定義
├── Dockerfile                     # Multi-stage (Alpine → Distroless)
├── buf.yaml                       # Buf 設定
├── sqlc.yaml                      # sqlc 設定
├── atlas.hcl                      # Atlas 設定
├── .golangci.yml                  # Lint 設定
├── go.mod / go.sum
└── .env.example
```

## Dependency Flow

```
handler → usecase → domain ← infra
                      ↑
              internal/domain (shared entities)
```

- `handler` は `usecase` と `gen/` (Proto 生成コード) に依存
- `usecase` は `domain` のみに依存 (Proto 生成コードに依存しない)
- `infra` は `domain` の Repository IF を実装し、`sqlcgen` と `database` に依存
- `domain` は外部に一切依存しない

## Detailed References

実装の詳細は以下のリファレンスを参照:

- **レイヤー別実装パターン** (domain/usecase/handler/infra の具体的コード): [references/layers.md](references/layers.md)
- **DI とサーバー構成** (main.go、ミドルウェアチェーン、条件分岐 DI): [references/di-and-server.md](references/di-and-server.md)
- **データベースパターン** (sqlc, トランザクション, スキーマ, pgx 型変換): [references/database.md](references/database.md)
- **認証設計** (OIDC フロー, セッション管理, ミドルウェア, Cookie): [references/authentication.md](references/authentication.md)
- **ツールチェーン** (Buf, sqlc, Atlas, golangci-lint, Dockerfile): [references/toolchain.md](references/toolchain.md)

## Quick Reference: 新機能追加チェックリスト

1. `proto/{feature}/v1/{feature}.proto` を作成 → `pnpm buf:generate`
2. `db/schema.sql` にテーブル追加 → `pnpm atlas:diff` → `pnpm atlas:apply`
3. `internal/{feature}/domain/` — Repository IF + エラー定義
4. `internal/{feature}/infra/queries.sql` — sqlc クエリ → `pnpm sqlc:generate`
5. `internal/{feature}/infra/store.go` — PostgreSQL 実装
6. `internal/{feature}/infra/memory_store.go` — インメモリ実装
7. `internal/{feature}/usecase/` — ビジネスロジック
8. `internal/{feature}/handler/` — ConnectRPC ハンドラー
9. `cmd/app/main.go` — DI 登録 + mux.Handle
10. `sqlc.yaml` — 新しいクエリパスを追加
