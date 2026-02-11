# レイヤー別実装パターン

実際のソースコードから抽出した各レイヤーの実装パターン。

---

## 1. Domain 層 (最内部)

外部に一切依存しない純粋なビジネスルール。

### 1.1 共有ドメインエンティティ (`internal/domain/`)

Feature 間で共有されるエンティティを配置。

```go
// internal/domain/user.go
package domain

import (
    "time"
    "github.com/google/uuid"
)

type User struct {
    ID        uuid.UUID
    Name      string
    Email     string
    CreatedAt time.Time
    UpdatedAt time.Time
}

func NewUser(name, email string) *User {
    now := time.Now()
    return &User{
        ID:        uuid.New(),
        Name:      name,
        Email:     email,
        CreatedAt: now,
        UpdatedAt: now,
    }
}
```

**パターン:**
- ファクトリ関数 `New{Entity}()` で ID とタイムスタンプを自動生成
- `uuid.UUID` 型 (string ではない) を ID に使用
- `time.Time` 型でタイムスタンプ管理

### 1.2 Feature ドメイン (`internal/{feature}/domain/`)

各 Feature 固有の Repository インターフェースとエラーを定義。

```go
// internal/user/domain/repository.go
package domain

import (
    "context"
    "errors"

    "github.com/google/uuid"
    sharedDomain "github.com/example/go-react-app/internal/domain"
)

var (
    ErrUserNotFound      = errors.New("user not found")
    ErrUserAlreadyExists = errors.New("user already exists")
)

type UserRepository interface {
    Create(ctx context.Context, user *sharedDomain.User) error
    FindByID(ctx context.Context, id uuid.UUID) (*sharedDomain.User, error)
    FindByEmail(ctx context.Context, email string) (*sharedDomain.User, error)
    Update(ctx context.Context, user *sharedDomain.User) error
    Delete(ctx context.Context, id uuid.UUID) error
    List(ctx context.Context, limit, offset int) ([]*sharedDomain.User, error)
}
```

**パターン:**
- エラーは `var Err{Feature}{Condition} = errors.New(...)` で公開定数として定義
- Repository IF は `context.Context` を第一引数に取る
- 共有エンティティは `sharedDomain` エイリアスで参照
- ID 型は `uuid.UUID` (string ではない)

### 1.3 Auth Feature ドメイン (複数 IF パターン)

認証のような複雑な Feature は複数のインターフェースに分割。

```go
// internal/auth/domain/identity.go
type Identity struct {
    Subject string  // OIDC "sub" claim
    Email   string
    Name    string
}

type Session struct {
    ID           string
    Identity     Identity
    AccessToken  string
    RefreshToken string
    IDToken      string
    ExpiresAt    time.Time
    CreatedAt    time.Time
}

type AuthState struct {
    State     string
    Nonce     string
    ExpiresAt time.Time
}
```

```go
// internal/auth/domain/repository.go
type SessionRepository interface {
    Save(ctx context.Context, session *Session) error
    FindByID(ctx context.Context, id string) (*Session, error)
    Delete(ctx context.Context, id string) error
    DeleteExpired(ctx context.Context) error
}

type StateRepository interface {
    Save(ctx context.Context, state *AuthState) error
    FindAndDelete(ctx context.Context, stateValue string) (*AuthState, error)
    DeleteExpired(ctx context.Context) error
}
```

```go
// internal/auth/domain/provider.go
type OIDCProvider interface {
    AuthorizationURL(state, nonce string, opts *AuthURLOptions) string
    Exchange(ctx context.Context, code, nonce string) (*OIDCTokens, error)
}
```

---

## 2. UseCase 層

ビジネスロジックを記述。Domain 層のみに依存。

### 2.1 基本パターン (User)

```go
// internal/user/usecase/user_usecase.go
package usecase

import (
    "context"
    "errors"
    "log/slog"

    "github.com/google/uuid"
    "github.com/example/go-react-app/internal/domain"
    userDomain "github.com/example/go-react-app/internal/user/domain"
)

type UserUseCase struct {
    repo   userDomain.UserRepository
    logger *slog.Logger
}

func NewUserUseCase(repo userDomain.UserRepository, logger *slog.Logger) *UserUseCase {
    return &UserUseCase{
        repo:   repo,
        logger: logger,
    }
}

func (uc *UserUseCase) CreateUser(ctx context.Context, name, email string) (*domain.User, error) {
    user := domain.NewUser(name, email)

    uc.logger.InfoContext(ctx, "creating user",
        slog.String("user_id", user.ID.String()),
        slog.String("email", email),
    )

    if err := uc.repo.Create(ctx, user); err != nil {
        uc.logger.ErrorContext(ctx, "failed to create user",
            slog.String("user_id", user.ID.String()),
            slog.Any("error", err),
        )
        return nil, err
    }

    uc.logger.InfoContext(ctx, "user created successfully",
        slog.String("user_id", user.ID.String()),
    )

    return user, nil
}

func (uc *UserUseCase) GetUser(ctx context.Context, id string) (*domain.User, error) {
    uid, err := uuid.Parse(id)
    if err != nil {
        uc.logger.WarnContext(ctx, "invalid user id format",
            slog.String("user_id", id),
            slog.Any("error", err),
        )
        return nil, userDomain.ErrUserNotFound
    }

    user, err := uc.repo.FindByID(ctx, uid)
    if err != nil {
        if !errors.Is(err, userDomain.ErrUserNotFound) {
            uc.logger.ErrorContext(ctx, "failed to get user",
                slog.String("user_id", id),
                slog.Any("error", err),
            )
        }
        return nil, err
    }

    return user, nil
}
```

**パターン:**
- コンストラクタ `New{Feature}UseCase(repo, logger)` で依存を注入
- `*slog.Logger` を依存として受け取り、構造化ログを出力
- ログレベル: `Info` = ビジネスイベント、`Warn` = 入力不正、`Error` = 予期しない障害
- `InfoContext` / `WarnContext` / `ErrorContext` でコンテキスト付きログ
- エラーは Domain 層のエラーをそのまま返す (ラップしない)
- string → uuid.UUID の変換は UseCase 層で行う

### 2.2 複雑な UseCase (Auth)

```go
// internal/auth/usecase/auth_usecase.go
const (
    sessionIDBytes = 32           // 256-bit entropy
    stateTTL       = 10 * time.Minute
    sessionTTL     = 24 * time.Hour
)

type AuthUseCase struct {
    provider domain.OIDCProvider
    sessions domain.SessionRepository
    states   domain.StateRepository
    logger   *slog.Logger
}

func NewAuthUseCase(
    provider domain.OIDCProvider,
    sessions domain.SessionRepository,
    states domain.StateRepository,
    logger *slog.Logger,
) *AuthUseCase { ... }
```

**パターン:**
- 定数で TTL やエントロピーサイズを定義
- 複数の Repository を受け取る
- `nil` チェック (provider が未設定の場合のグレースフルデグレード)

---

## 3. Handler 層

HTTP/ConnectRPC のリクエストを受け取り、UseCase を呼び出す。

### 3.1 ConnectRPC ハンドラー (User)

```go
// internal/user/handler/user_handler.go
package handler

import (
    "context"
    "errors"

    "connectrpc.com/connect"

    userv1 "github.com/example/go-react-app/gen/user/v1"
    "github.com/example/go-react-app/gen/user/v1/userv1connect"
    "github.com/example/go-react-app/internal/user/domain"
    "github.com/example/go-react-app/internal/user/usecase"
)

type UserHandler struct {
    uc *usecase.UserUseCase
}

// コンパイル時インターフェース検証
var _ userv1connect.UserServiceHandler = (*UserHandler)(nil)

func NewUserHandler(uc *usecase.UserUseCase) *UserHandler {
    return &UserHandler{uc: uc}
}

func (h *UserHandler) CreateUser(
    ctx context.Context,
    req *connect.Request[userv1.CreateUserRequest],
) (*connect.Response[userv1.CreateUserResponse], error) {
    user, err := h.uc.CreateUser(ctx, req.Msg.Name, req.Msg.Email)
    if err != nil {
        if errors.Is(err, domain.ErrUserAlreadyExists) {
            return nil, connect.NewError(connect.CodeAlreadyExists, err)
        }
        return nil, connect.NewError(connect.CodeInternal, err)
    }
    return connect.NewResponse(&userv1.CreateUserResponse{
        User: &userv1.User{
            Id:    user.ID.String(),
            Name:  user.Name,
            Email: user.Email,
        },
    }), nil
}
```

**パターン:**
- `var _ {Service}Handler = (*{Handler})(nil)` でコンパイル時インターフェース検証
- `req.Msg.{Field}` でリクエストフィールドにアクセス
- `connect.NewResponse(...)` でレスポンスを返す
- Domain → Proto 変換はハンドラー内でインラインで行う
- Domain エラー → ConnectRPC コードマッピング:
  - `ErrNotFound` → `connect.CodeNotFound`
  - `ErrAlreadyExists` → `connect.CodeAlreadyExists`
  - その他 → `connect.CodeInternal`

### 3.2 HTTP ハンドラー (Auth)

認証のように HTTP リダイレクトが必要な場合は標準 `net/http` を使用。

```go
// internal/auth/handler/auth_handler.go
type AuthHandler struct {
    uc  *usecase.AuthUseCase
    cfg config.AuthConfig
    log *slog.Logger
}

func NewAuthHandler(uc *usecase.AuthUseCase, cfg config.AuthConfig, logger *slog.Logger) *AuthHandler {
    return &AuthHandler{uc: uc, cfg: cfg, log: logger}
}

// Register adds auth routes to the mux.
func (h *AuthHandler) Register(mux *http.ServeMux) {
    mux.HandleFunc("GET /auth/login", h.Login)
    mux.HandleFunc("GET /auth/callback", h.Callback)
    mux.HandleFunc("POST /auth/logout", h.Logout)
    mux.HandleFunc("GET /auth/me", h.Me)
}
```

**パターン:**
- `Register(mux)` メソッドでルートをまとめて登録
- Go 1.22+ のメソッドパターン (`"GET /auth/login"`) を使用
- `config.AuthConfig` を直接受け取る (設定値構造体)
- Cookie 操作はハンドラー層の責務

---

## 4. Infra 層

Domain の Repository IF を実装する具体的なデータアクセス層。

### 4.1 PostgreSQL Store (`store.go`)

```go
// internal/user/infra/store.go
package infra

import (
    "context"
    "errors"
    "time"

    "github.com/google/uuid"
    "github.com/jackc/pgx/v5"
    "github.com/jackc/pgx/v5/pgtype"
    "github.com/jackc/pgx/v5/pgxpool"

    "github.com/example/go-react-app/internal/database"
    "github.com/example/go-react-app/internal/domain"
    userDomain "github.com/example/go-react-app/internal/user/domain"
    "github.com/example/go-react-app/internal/user/infra/sqlcgen"
)

type UserStore struct {
    pool *pgxpool.Pool
}

func NewUserStore(pool *pgxpool.Pool) *UserStore {
    return &UserStore{pool: pool}
}

// queries() はトランザクション対応の核心パターン
func (s *UserStore) queries(ctx context.Context) *sqlcgen.Queries {
    if tx := database.GetTx(ctx); tx != nil {
        return sqlcgen.New(tx)
    }
    return sqlcgen.New(s.pool)
}

func (s *UserStore) Create(ctx context.Context, user *domain.User) error {
    return s.queries(ctx).CreateUser(ctx, sqlcgen.CreateUserParams{
        ID:        toPgUUID(user.ID),
        Name:      user.Name,
        Email:     user.Email,
        CreatedAt: toPgTimestamptz(user.CreatedAt),
        UpdatedAt: toPgTimestamptz(user.UpdatedAt),
    })
}

func (s *UserStore) FindByID(ctx context.Context, id uuid.UUID) (*domain.User, error) {
    row, err := s.queries(ctx).GetUserByID(ctx, toPgUUID(id))
    if err != nil {
        if errors.Is(err, pgx.ErrNoRows) {
            return nil, userDomain.ErrUserNotFound
        }
        return nil, err
    }
    return toUser(row), nil
}
```

**パターン:**
- `*pgxpool.Pool` をコンストラクタで受け取る
- `queries(ctx)` メソッドでトランザクション透過的に sqlc Queries を取得
- `pgx.ErrNoRows` → Domain エラーへの変換
- 型変換ヘルパー関数: `toPgUUID()`, `toPgTimestamptz()`, `toUser()`

### 4.2 型変換ヘルパー

```go
// pgtype ↔ domain 変換
func toPgUUID(id uuid.UUID) pgtype.UUID {
    return pgtype.UUID{Bytes: id, Valid: true}
}

func toPgTimestamptz(t time.Time) pgtype.Timestamptz {
    return pgtype.Timestamptz{Time: t, Valid: true}
}

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

### 4.3 Memory Store (`memory_store.go`)

```go
// internal/user/infra/memory_store.go
type MemoryStore struct {
    mu    sync.RWMutex
    users map[uuid.UUID]*domain.User
}

func NewMemoryStore() *MemoryStore {
    return &MemoryStore{users: make(map[uuid.UUID]*domain.User)}
}

func (s *MemoryStore) Create(_ context.Context, user *domain.User) error {
    s.mu.Lock()
    defer s.mu.Unlock()
    // メール重複チェック
    for _, existing := range s.users {
        if existing.Email == user.Email {
            return userDomain.ErrUserAlreadyExists
        }
    }
    s.users[user.ID] = user
    return nil
}

func (s *MemoryStore) FindByID(_ context.Context, id uuid.UUID) (*domain.User, error) {
    s.mu.RLock()
    defer s.mu.RUnlock()
    user, ok := s.users[id]
    if !ok {
        return nil, userDomain.ErrUserNotFound
    }
    return user, nil
}
```

**パターン:**
- `sync.RWMutex` でスレッドセーフ
- Context は使わないが引数として受け取る (`_ context.Context`)
- PostgreSQL Store と同じ Domain エラーを返す (インターフェース互換)
- Read は `RLock()`、Write は `Lock()` で使い分け

### 4.4 Adapter パターン (Auth Store)

1 つの Store が複数の Repository IF を実装する場合のパターン。

```go
// internal/auth/infra/store.go
type AuthStore struct {
    pool *pgxpool.Pool
}

// SessionRepository と StateRepository の両方を実装
// Adapter で分離して返す

func (s *AuthStore) SessionRepo() domain.SessionRepository {
    return &sessionRepoAdapter{store: s}
}

func (s *AuthStore) StateRepo() domain.StateRepository {
    return &stateRepoAdapter{store: s}
}

type sessionRepoAdapter struct{ store *AuthStore }

func (a *sessionRepoAdapter) Save(ctx context.Context, session *domain.Session) error {
    return a.store.Save(ctx, session)
}
// ... 他メソッド
```

---

## 5. 構造化ログパターン

slog を全レイヤーで統一的に使用。

```go
// UseCase 層のログパターン
uc.logger.InfoContext(ctx, "creating user",
    slog.String("user_id", user.ID.String()),
    slog.String("email", email),
)

uc.logger.WarnContext(ctx, "invalid user id format",
    slog.String("user_id", id),
    slog.Any("error", err),
)

uc.logger.ErrorContext(ctx, "failed to create user",
    slog.String("user_id", user.ID.String()),
    slog.Any("error", err),
)
```

**ログレベル規約:**
| レベル | 用途 | 例 |
|-------|------|-----|
| `Info` | 正常なビジネスイベント | ユーザー作成成功、セッション作成 |
| `Warn` | 想定内のエッジケース | 不正 ID フォーマット、認証失敗 |
| `Error` | 予期しないシステムエラー | DB 接続失敗、コード交換失敗 |

**フィールド規約:**
- ID 系: `slog.String("user_id", ...)`, `slog.String("session_id_prefix", ...)`
- エラー: `slog.Any("error", err)`
- ビジネス値: `slog.String("email", ...)`, `slog.String("path", ...)`
