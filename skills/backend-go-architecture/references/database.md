# データベースパターン

sqlc による型安全 SQL、pgx/v5 によるトランザクション管理、スキーマ定義。

---

## スキーマ定義 (`db/schema.sql`)

Single Source of Truth。Atlas でマイグレーションを生成。

```sql
-- Users table
CREATE TABLE users (
    id UUID PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_created_at ON users(created_at DESC);

-- Auth sessions table
CREATE TABLE auth_sessions (
    id TEXT PRIMARY KEY,
    subject VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL,
    name VARCHAR(255) NOT NULL DEFAULT '',
    access_token TEXT NOT NULL,
    refresh_token TEXT NOT NULL DEFAULT '',
    id_token TEXT NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_auth_sessions_expires_at ON auth_sessions(expires_at);

-- Auth states table
CREATE TABLE auth_states (
    state TEXT PRIMARY KEY,
    nonce TEXT NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX idx_auth_states_expires_at ON auth_states(expires_at);
```

**スキーマ規約:**
- UUID 主キー (User)、TEXT 主キー (Auth: ランダム hex)
- `created_at` / `updated_at` は `TIMESTAMPTZ NOT NULL`
- UNIQUE 制約 + 検索用インデックスを明示
- 期限付きデータ (session/state) には `expires_at` インデックス

---

## sqlc クエリ定義

### User Feature (`internal/user/infra/queries.sql`)

```sql
-- name: GetUserByID :one
SELECT id, name, email, created_at, updated_at
FROM users WHERE id = $1;

-- name: GetUserByEmail :one
SELECT id, name, email, created_at, updated_at
FROM users WHERE email = $1;

-- name: ListUsers :many
SELECT id, name, email, created_at, updated_at
FROM users ORDER BY created_at DESC
LIMIT $1 OFFSET $2;

-- name: CreateUser :exec
INSERT INTO users (id, name, email, created_at, updated_at)
VALUES ($1, $2, $3, $4, $5);

-- name: UpdateUser :exec
UPDATE users SET name = $2, email = $3, updated_at = $4
WHERE id = $1;

-- name: DeleteUser :exec
DELETE FROM users WHERE id = $1;
```

### Auth Feature (`internal/auth/infra/queries.sql`)

```sql
-- name: UpsertSession :exec
INSERT INTO auth_sessions (id, subject, email, name, access_token, refresh_token, id_token, expires_at, created_at)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
ON CONFLICT (id) DO UPDATE SET
    subject = EXCLUDED.subject, email = EXCLUDED.email, name = EXCLUDED.name,
    access_token = EXCLUDED.access_token, refresh_token = EXCLUDED.refresh_token,
    id_token = EXCLUDED.id_token, expires_at = EXCLUDED.expires_at;

-- name: GetSessionByID :one
SELECT id, subject, email, name, access_token, refresh_token, id_token, expires_at, created_at
FROM auth_sessions WHERE id = $1;

-- name: DeleteSession :exec
DELETE FROM auth_sessions WHERE id = $1;

-- name: DeleteExpiredSessions :exec
DELETE FROM auth_sessions WHERE expires_at < NOW();

-- name: InsertState :exec
INSERT INTO auth_states (state, nonce, expires_at) VALUES ($1, $2, $3);

-- name: FindAndDeleteState :one
DELETE FROM auth_states WHERE state = $1 RETURNING state, nonce, expires_at;

-- name: DeleteExpiredStates :exec
DELETE FROM auth_states WHERE expires_at < NOW();
```

**sqlc アノテーション規約:**
| アノテーション | 用途 | 戻り値 |
|-------------|------|--------|
| `:one` | 1行取得 (見つからなければ `pgx.ErrNoRows`) | `(Row, error)` |
| `:many` | 複数行取得 | `([]Row, error)` |
| `:exec` | INSERT/UPDATE/DELETE (戻り値なし) | `error` |

**SQL パターン:**
- UPSERT: `ON CONFLICT (pk) DO UPDATE SET ...` + `EXCLUDED.column`
- DELETE + RETURNING: State のアトミックな取得+削除
- ページネーション: `ORDER BY ... LIMIT $1 OFFSET $2`

---

## sqlc 設定 (`sqlc.yaml`)

```yaml
version: "2"
sql:
  - engine: "postgresql"
    queries: "internal/user/infra/queries.sql"
    schema: "db/schema.sql"
    gen:
      go:
        package: "sqlcgen"
        out: "internal/user/infra/sqlcgen"
        sql_package: "pgx/v5"
        emit_json_tags: true
        emit_prepared_queries: false
        emit_interface: false
        emit_exact_table_names: false
        emit_empty_slices: true
  - engine: "postgresql"
    queries: "internal/auth/infra/queries.sql"
    schema: "db/schema.sql"
    gen:
      go:
        package: "sqlcgen"
        out: "internal/auth/infra/sqlcgen"
        sql_package: "pgx/v5"
        emit_json_tags: true
        emit_prepared_queries: false
        emit_interface: false
        emit_exact_table_names: false
        emit_empty_slices: true
```

**新 Feature 追加時:** `sql:` 配列に新しいエントリを追加:

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

**設定ポイント:**
- `sql_package: "pgx/v5"` — pgx v5 型 (`pgtype.UUID`, `pgtype.Timestamptz`) を生成
- `emit_empty_slices: true` — 空結果を `nil` ではなく `[]` で返す (JSON `null` 回避)
- `emit_json_tags: true` — 生成構造体に JSON タグ付与

---

## トランザクション管理

### Context 埋め込みパターン (`internal/database/tx.go`)

```go
package database

import (
    "context"
    "github.com/jackc/pgx/v5"
)

type ctxKey string
const txKey ctxKey = "pgx_tx"

func WithTx(ctx context.Context, tx pgx.Tx) context.Context {
    return context.WithValue(ctx, txKey, tx)
}

func GetTx(ctx context.Context) pgx.Tx {
    tx, _ := ctx.Value(txKey).(pgx.Tx)
    return tx
}
```

### Store での使用

```go
// 全 Store の queries() メソッドが同じパターン
func (s *UserStore) queries(ctx context.Context) *sqlcgen.Queries {
    if tx := database.GetTx(ctx); tx != nil {
        return sqlcgen.New(tx)  // トランザクション内
    }
    return sqlcgen.New(s.pool)  // 通常のコネクションプール
}
```

### UseCase でのトランザクション使用

```go
// 複数 Repository を跨ぐ原子的操作 (パターン例)
func (uc *SomeUseCase) DoSomething(ctx context.Context) error {
    tx, err := uc.pool.Begin(ctx)
    if err != nil { return err }
    defer tx.Rollback(ctx)

    ctx = database.WithTx(ctx, tx)

    // 以降、全 Store が自動的に tx を使用
    if err := uc.repoA.Create(ctx, ...); err != nil { return err }
    if err := uc.repoB.Create(ctx, ...); err != nil { return err }

    return tx.Commit(ctx)
}
```

---

## pgx/v5 型変換ヘルパー

各 Store に型変換ヘルパーを定義。

```go
// uuid.UUID → pgtype.UUID
func toPgUUID(id uuid.UUID) pgtype.UUID {
    return pgtype.UUID{Bytes: id, Valid: true}
}

// time.Time → pgtype.Timestamptz
func toPgTimestamptz(t time.Time) pgtype.Timestamptz {
    return pgtype.Timestamptz{Time: t, Valid: true}
}

// sqlcgen.User → domain.User
func toUser(row sqlcgen.User) *domain.User {
    return &domain.User{
        ID:        uuid.UUID(row.ID.Bytes),
        Name:      row.Name,
        Email:     row.Email,
        CreatedAt: row.CreatedAt.Time,
        UpdatedAt: row.UpdatedAt.Time,
    }
}
```

**pgx/v5 型マッピング:**
| Go 型 | pgtype 型 | SQL 型 |
|------|-----------|--------|
| `uuid.UUID` | `pgtype.UUID` | `UUID` |
| `time.Time` | `pgtype.Timestamptz` | `TIMESTAMPTZ` |
| `string` | `string` | `VARCHAR` / `TEXT` |
| `int32` | `int32` | `INTEGER` |

---

## エラーハンドリング (Infra 層)

```go
func (s *UserStore) FindByID(ctx context.Context, id uuid.UUID) (*domain.User, error) {
    row, err := s.queries(ctx).GetUserByID(ctx, toPgUUID(id))
    if err != nil {
        if errors.Is(err, pgx.ErrNoRows) {
            return nil, userDomain.ErrUserNotFound  // Domain エラーに変換
        }
        return nil, err  // DB エラーはそのまま返す
    }
    return toUser(row), nil
}
```

**エラー変換規約:**
- `pgx.ErrNoRows` → Feature 固有の `ErrNotFound`
- その他の DB エラー → そのまま上位に伝播
- Handler 層で最終的に ConnectRPC エラーコードに変換

---

## Atlas マイグレーション (`atlas.hcl`)

```hcl
variable "db_url" {
  type    = string
  default = getenv("DATABASE_URL")
}

env "local" {
  src = "file://db/schema.sql"     # スキーマの Source of Truth
  url = var.db_url                 # 対象 DB
  dev = "docker://postgres/16/dev?search_path=public"  # Dev DB (diff 用)
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

**マイグレーション手順:**
1. `db/schema.sql` を編集
2. `pnpm atlas:diff` — 差分からマイグレーション SQL を自動生成
3. `pnpm atlas:apply` — マイグレーションを適用
