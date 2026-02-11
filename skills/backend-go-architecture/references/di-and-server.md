# DI とサーバー構成

`cmd/app/main.go` のエントリーポイント、DI、ミドルウェアチェーン、サーバー設定。

---

## エントリーポイント構造

```go
// cmd/app/main.go
func main() {
    if err := run(); err != nil {
        fmt.Fprintf(os.Stderr, "error: %v\n", err)
        os.Exit(1)
    }
}

func run() error {
    // 1. .env 読み込み (なくても OK)
    _ = godotenv.Load()

    // 2. 構造化ロガー初期化 (JSON)
    logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
        Level: slog.LevelInfo,
    }))
    slog.SetDefault(logger)

    // 3. 設定読み込み
    cfg := config.Load()

    // 4. DB プール初期化 (postgres モードのみ)
    pool, poolCleanup, err := newPool(cfg, logger)
    if err != nil { return err }
    defer poolCleanup()

    // 5. Feature ごとの DI
    // ... (後述)

    // 6. ハンドラー登録
    // 7. ミドルウェアチェーン構築
    // 8. サーバー起動

    return srv.ListenAndServe()
}
```

---

## DI パターン

### 条件分岐 DI (Memory / PostgreSQL)

`DB_DRIVER` 環境変数で実装を切り替える。

```go
// DB プール (postgres のみ)
func newPool(cfg *config.Config, logger *slog.Logger) (*pgxpool.Pool, func(), error) {
    if cfg.Database.Driver != "postgres" {
        return nil, func() {}, nil  // Memory モードではプール不要
    }
    pool, err := pgxpool.New(context.Background(), cfg.Database.DSN)
    if err != nil { return nil, nil, fmt.Errorf("create connection pool: %w", err) }
    if err := pool.Ping(context.Background()); err != nil {
        pool.Close()
        return nil, nil, fmt.Errorf("connect to database: %w", err)
    }
    logger.Info("connected to PostgreSQL database")
    return pool, func() { pool.Close() }, nil
}

// User Repository
func newUserRepository(cfg *config.Config, pool *pgxpool.Pool, logger *slog.Logger) userDomain.UserRepository {
    if cfg.Database.Driver == "postgres" && pool != nil {
        return userInfra.NewUserStore(pool)
    }
    logger.Info("using in-memory user storage")
    return userInfra.NewMemoryStore()
}

// Auth Repository (複数 IF を返す)
func newAuthRepositories(cfg *config.Config, pool *pgxpool.Pool, logger *slog.Logger) (domain.SessionRepository, domain.StateRepository) {
    if cfg.Database.Driver == "postgres" && pool != nil {
        store := authInfra.NewAuthStore(pool)
        return store.SessionRepo(), store.StateRepo()
    }
    logger.Info("using in-memory auth storage")
    memStore := authInfra.NewMemoryAuthStore()
    return memStore.SessionRepo(), memStore.StateRepo()
}
```

### OIDC Provider (nil-safe)

```go
func newOIDCProvider(cfg *config.Config, logger *slog.Logger) domain.OIDCProvider {
    if cfg.OIDC.IssuerURL == "" {
        logger.Warn("OIDC not configured: auth endpoints will not work")
        return nil  // nil を返す → UseCase で ErrOIDCNotConfigured
    }
    provider, err := authInfra.NewOIDCProvider(context.Background(), cfg.OIDC)
    if err != nil {
        logger.Error("failed to initialize OIDC provider", slog.Any("error", err))
        logger.Warn("continuing without OIDC: auth endpoints will not work")
        return nil
    }
    return provider
}
```

### Feature DI チェーン

```go
// User DI
userRepo := newUserRepository(cfg, pool, logger)
userUC := usecase.NewUserUseCase(userRepo, logger)
userHandler := handler.NewUserHandler(userUC)

// Auth DI
sessionRepo, stateRepo := newAuthRepositories(cfg, pool, logger)
oidcProvider := newOIDCProvider(cfg, logger)
authUC := authUsecase.NewAuthUseCase(oidcProvider, sessionRepo, stateRepo, logger)
authH := authHandler.NewAuthHandler(authUC, cfg.Auth, logger)
```

**DI の順序:**
1. Repository (infra) のインスタンス化
2. UseCase のインスタンス化 (Repository を注入)
3. Handler のインスタンス化 (UseCase を注入)

---

## ハンドラー登録

```go
mux := http.NewServeMux()

// 1. gRPC Health Check (標準プロトコル)
checker := grpchealth.NewStaticChecker(
    userv1connect.UserServiceName,
)
mux.Handle(grpchealth.NewHandler(checker))

// 2. Auth エンドポイント (/auth/*)
authH.Register(mux)

// 3. ConnectRPC ハンドラー
path, h := userv1connect.NewUserServiceHandler(userHandler)
mux.Handle(path, h)
```

**新機能追加時:**
```go
// 新しい ConnectRPC サービスの追加
{feature}Path, {feature}H := {feature}v1connect.New{Feature}ServiceHandler({feature}Handler)
mux.Handle({feature}Path, {feature}H)

// Health Check にサービス名を追加
checker := grpchealth.NewStaticChecker(
    userv1connect.UserServiceName,
    {feature}v1connect.{Feature}ServiceName,  // 追加
)
```

---

## ミドルウェアチェーン

```
外部リクエスト
    ↓
CORS Handler (最外層)
    ↓
Auth Middleware
    ↓
Mux (ルートディスパッチ)
    ├── /grpc.health.v1.Health/Check  (public)
    ├── /auth/*                        (public)
    └── /user.v1.UserService/*         (要認証)
```

```go
// Middleware 構築
authed := authMiddleware.Auth(authUC, logger)(mux)

corsHandler := cors.New(cors.Options{
    AllowedOrigins:   cfg.Server.AllowedOrigins,
    AllowedMethods:   append(connectcors.AllowedMethods(), "GET", "POST"),
    AllowedHeaders:   append(connectcors.AllowedHeaders(), "Cookie"),
    ExposedHeaders:   connectcors.ExposedHeaders(),
    AllowCredentials: true,
}).Handler(authed)
```

**CORS 設定のポイント:**
- `connectcors.AllowedMethods()` に `GET`, `POST` を追加 (auth エンドポイント用)
- `connectcors.AllowedHeaders()` に `Cookie` を追加 (セッション認証用)
- `AllowCredentials: true` (Cookie 送信を許可)

---

## サーバー設定

```go
addr := ":" + cfg.Server.Port
srv := &http.Server{
    Addr:              addr,
    Handler:           corsHandler,
    ReadHeaderTimeout: 10 * time.Second,
}

// h2c (HTTP/2 Cleartext) サポート — Go 1.24+ native
srv.Protocols = &http.Protocols{}
srv.Protocols.SetHTTP1(true)
srv.Protocols.SetUnencryptedHTTP2(true)
```

**ポイント:**
- `ReadHeaderTimeout: 10s` で Slowloris 攻撃を防止
- h2c を有効化 (ConnectRPC は HTTP/2 で gRPC をサポート)
- Go 1.24+ の native `http.Protocols` API を使用 (`golang.org/x/net/http2` 不要)

---

## 設定管理 (`internal/config/config.go`)

```go
type Config struct {
    Server   ServerConfig
    Database DatabaseConfig
    OIDC     OIDCConfig
    Auth     AuthConfig
}

type ServerConfig struct {
    Port           string   // default: "8080"
    AllowedOrigins []string // default: ["http://localhost:5173"]
}

type DatabaseConfig struct {
    Driver string // "memory" or "postgres"
    DSN    string
}

type OIDCConfig struct {
    IssuerURL    string
    ClientID     string
    ClientSecret string
    RedirectURL  string   // default: "http://localhost:8080/auth/callback"
    Scopes       []string // default: ["openid", "profile", "email"]
}

type AuthConfig struct {
    FrontendURL  string // default: "http://localhost:5173"
    CookieSecure bool   // default: false
}

func Load() *Config {
    return &Config{
        Server: ServerConfig{
            Port:           getEnv("SERVER_PORT", "8080"),
            AllowedOrigins: getEnvSlice("CORS_ALLOWED_ORIGINS", []string{"http://localhost:5173"}),
        },
        Database: DatabaseConfig{
            Driver: getEnv("DB_DRIVER", "memory"),
            DSN:    getEnv("DATABASE_URL", ""),
        },
        OIDC: OIDCConfig{
            IssuerURL:    getEnv("OIDC_ISSUER_URL", ""),
            ClientID:     getEnv("OIDC_CLIENT_ID", ""),
            ClientSecret: getEnv("OIDC_CLIENT_SECRET", ""),
            RedirectURL:  getEnv("OIDC_REDIRECT_URL", "http://localhost:8080/auth/callback"),
            Scopes:       getEnvSlice("OIDC_SCOPES", []string{"openid", "profile", "email"}),
        },
        Auth: AuthConfig{
            FrontendURL:  getEnv("AUTH_FRONTEND_URL", "http://localhost:5173"),
            CookieSecure: getEnv("AUTH_COOKIE_SECURE", "false") == "true",
        },
    }
}
```

**パターン:**
- `getEnv(key, default)` — 環境変数がなければデフォルト値
- `getEnvSlice(key, default)` — カンマ区切りの環境変数をスライスに変換
- ゼロコンフィグで開発可能 (全てデフォルト値あり)

---

## Import エイリアス規約

```go
import (
    // 標準ライブラリ

    // 外部ライブラリ
    connectcors "connectrpc.com/cors"

    // Proto 生成コード
    userv1 "github.com/example/go-react-app/gen/user/v1"
    "github.com/example/go-react-app/gen/user/v1/userv1connect"

    // 内部パッケージ (同名パッケージはエイリアス)
    authHandler "github.com/example/go-react-app/internal/auth/handler"
    authInfra "github.com/example/go-react-app/internal/auth/infra"
    authMiddleware "github.com/example/go-react-app/internal/auth/middleware"
    authUsecase "github.com/example/go-react-app/internal/auth/usecase"
    "github.com/example/go-react-app/internal/config"
    userDomain "github.com/example/go-react-app/internal/user/domain"
    "github.com/example/go-react-app/internal/user/handler"
    userInfra "github.com/example/go-react-app/internal/user/infra"
    "github.com/example/go-react-app/internal/user/usecase"
)
```

**エイリアス規約:**
- 異なる Feature の同名パッケージ → `{feature}{Layer}` (例: `authHandler`, `userDomain`)
- 衝突しないパッケージ → エイリアスなし (例: `config`, `handler`, `usecase`)
- Proto 生成コード → `{feature}v1` (例: `userv1`)
