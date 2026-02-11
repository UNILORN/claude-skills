# 認証設計

OIDC Authorization Code Flow + サーバーサイドセッション管理の実装パターン。

---

## 認証フロー (シーケンス)

```
ブラウザ                    バックエンド                  OIDC プロバイダー
  │                           │                              │
  │  GET /auth/login          │                              │
  │──────────────────────────>│                              │
  │                           │  state + nonce 生成          │
  │                           │  auth_states に保存          │
  │  302 Redirect             │                              │
  │<──────────────────────────│                              │
  │                           │                              │
  │  認可URL へアクセス       │                              │
  │─────────────────────────────────────────────────────────>│
  │                           │                              │
  │  ユーザー認証 + 同意      │                              │
  │<─────────────────────────────────────────────────────────│
  │                           │                              │
  │  GET /auth/callback?code=X&state=Y                       │
  │──────────────────────────>│                              │
  │                           │  state 検証 (FindAndDelete)  │
  │                           │  code → tokens 交換 ─────────>│
  │                           │<──────────────────────────────│
  │                           │  ID Token 署名検証           │
  │                           │  nonce 検証                  │
  │                           │  セッション作成              │
  │  Set-Cookie: session_id   │  auth_sessions に保存        │
  │  302 Redirect → frontend  │                              │
  │<──────────────────────────│                              │
  │                           │                              │
  │  以降のリクエスト (Cookie 付き)                           │
  │──────────────────────────>│                              │
  │                           │  Auth Middleware:             │
  │                           │  session_id → Identity 取得  │
  │                           │  ctx に Identity 埋め込み    │
```

---

## Auth エンドポイント

| メソッド | パス | 認証 | 説明 |
|---------|------|------|------|
| GET | `/auth/login` | 不要 | OIDC 認可 URL へリダイレクト |
| GET | `/auth/callback` | 不要 | OIDC コールバック処理 |
| POST | `/auth/logout` | Cookie | セッション破棄 + Cookie 削除 |
| GET | `/auth/me` | Cookie | 認証済みユーザー情報 (JSON) |

### Login ハンドラー

```go
func (h *AuthHandler) Login(w http.ResponseWriter, r *http.Request) {
    // オプション: ?prompt=login で再認証を強制
    var opts *domain.AuthURLOptions
    if prompt := r.URL.Query().Get("prompt"); prompt != "" {
        opts = &domain.AuthURLOptions{Prompt: prompt}
    }

    url, err := h.uc.StartLogin(r.Context(), opts)
    if err != nil {
        if errors.Is(err, domain.ErrOIDCNotConfigured) {
            http.Error(w, "OIDC authentication is not configured", http.StatusServiceUnavailable)
            return
        }
        http.Error(w, "Internal Server Error", http.StatusInternalServerError)
        return
    }
    http.Redirect(w, r, url, http.StatusFound)
}
```

### Callback ハンドラー

```go
func (h *AuthHandler) Callback(w http.ResponseWriter, r *http.Request) {
    code := r.URL.Query().Get("code")
    state := r.URL.Query().Get("state")

    if code == "" || state == "" {
        http.Error(w, "missing code or state parameter", http.StatusBadRequest)
        return
    }

    sessionID, err := h.uc.HandleCallback(r.Context(), code, state)
    if err != nil { /* エラー処理 */ }

    // セッション Cookie を設定
    http.SetCookie(w, &http.Cookie{
        Name:     "session_id",
        Value:    sessionID,
        Path:     "/",
        HttpOnly: true,
        Secure:   h.cfg.CookieSecure,
        SameSite: http.SameSiteLaxMode,
        MaxAge:   86400, // 24 hours
    })

    // フロントエンドへリダイレクト
    http.Redirect(w, r, h.cfg.FrontendURL, http.StatusFound)
}
```

---

## Cookie 設定

```go
http.SetCookie(w, &http.Cookie{
    Name:     "session_id",          // Cookie 名
    Value:    sessionID,             // 256-bit ランダム hex
    Path:     "/",                   // 全パスに送信
    HttpOnly: true,                  // JavaScript からアクセス不可
    Secure:   h.cfg.CookieSecure,    // 本番は true (HTTPS only)
    SameSite: http.SameSiteLaxMode,  // CSRF 防止
    MaxAge:   86400,                 // 24 時間
})
```

**セキュリティ属性:**
- `HttpOnly: true` — XSS 耐性 (JS アクセス不可)
- `Secure: true` (本番) — HTTPS でのみ送信
- `SameSite=Lax` — CSRF 防止 (GET リダイレクトは許可)

---

## Auth Middleware

```go
// internal/auth/middleware/auth.go
func Auth(uc *usecase.AuthUseCase, logger *slog.Logger) func(http.Handler) http.Handler {
    return func(next http.Handler) http.Handler {
        return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
            // 1. パブリックパスはスキップ
            for _, p := range publicPaths {
                if r.URL.Path == p {
                    next.ServeHTTP(w, r)
                    return
                }
            }

            // 2. Cookie 認証を試行
            if cookie, err := r.Cookie("session_id"); err == nil && cookie.Value != "" {
                identity, err := uc.GetIdentity(r.Context(), cookie.Value)
                if err == nil {
                    ctx := WithIdentity(r.Context(), identity)
                    next.ServeHTTP(w, r.WithContext(ctx))
                    return
                }
            }

            // 3. Bearer トークン認証を試行
            if auth := r.Header.Get("Authorization"); strings.HasPrefix(auth, "Bearer ") {
                token := strings.TrimPrefix(auth, "Bearer ")
                identity, err := uc.GetIdentity(r.Context(), token)
                if err == nil {
                    ctx := WithIdentity(r.Context(), identity)
                    next.ServeHTTP(w, r.WithContext(ctx))
                    return
                }
            }

            // 4. 未認証
            http.Error(w, "Unauthorized", http.StatusUnauthorized)
        })
    }
}
```

### パブリックパス (認証不要)

```go
var publicPaths = []string{
    "/auth/login",
    "/auth/callback",
    "/grpc.health.v1.Health/Check",
}
```

**新エンドポイント追加時:** 認証不要なパスは `publicPaths` に追加。

### Identity Context 伝播

```go
type identityKey struct{}

func WithIdentity(ctx context.Context, identity *domain.Identity) context.Context {
    return context.WithValue(ctx, identityKey{}, identity)
}

func GetIdentity(ctx context.Context) *domain.Identity {
    identity, _ := ctx.Value(identityKey{}).(*domain.Identity)
    return identity
}
```

**Handler での使用:**
```go
// ConnectRPC ハンドラーや HTTP ハンドラーから Identity を取得
identity := middleware.GetIdentity(ctx)
if identity != nil {
    // identity.Subject, identity.Email, identity.Name が利用可能
}
```

---

## UseCase (Auth ビジネスロジック)

### 定数

```go
const (
    sessionIDBytes = 32           // 256-bit entropy
    stateTTL       = 10 * time.Minute
    sessionTTL     = 24 * time.Hour
)
```

### StartLogin

```go
func (uc *AuthUseCase) StartLogin(ctx context.Context, opts *domain.AuthURLOptions) (string, error) {
    if uc.provider == nil {
        return "", domain.ErrOIDCNotConfigured
    }
    state, _ := generateRandomHex(sessionIDBytes)
    nonce, _ := generateRandomHex(sessionIDBytes)

    authState := &domain.AuthState{
        State: state, Nonce: nonce,
        ExpiresAt: time.Now().Add(stateTTL),
    }
    uc.states.Save(ctx, authState)

    return uc.provider.AuthorizationURL(state, nonce, opts), nil
}
```

### HandleCallback

```go
func (uc *AuthUseCase) HandleCallback(ctx context.Context, code, stateParam string) (string, error) {
    // 1. State 検証 (FindAndDelete でアトミックに取得+削除)
    authState, err := uc.states.FindAndDelete(ctx, stateParam)
    // 2. 期限チェック
    // 3. Code → Tokens 交換 (nonce 検証含む)
    tokens, err := uc.provider.Exchange(ctx, code, authState.Nonce)
    // 4. セッション作成
    session := &domain.Session{
        ID: sessionID,
        Identity: tokens.Claims,
        // ...
        ExpiresAt: time.Now().Add(sessionTTL),
    }
    uc.sessions.Save(ctx, session)
    return sessionID, nil
}
```

---

## OIDC Provider 実装

```go
// internal/auth/infra/oidc_provider.go
type OIDCProvider struct {
    provider *oidc.Provider
    verifier *oidc.IDTokenVerifier
    oauth    oauth2.Config
}

func NewOIDCProvider(ctx context.Context, cfg config.OIDCConfig) (*OIDCProvider, error) {
    // OIDC Discovery
    provider, err := oidc.NewProvider(ctx, cfg.IssuerURL)
    verifier := provider.Verifier(&oidc.Config{ClientID: cfg.ClientID})
    oauthCfg := oauth2.Config{
        ClientID: cfg.ClientID, ClientSecret: cfg.ClientSecret,
        RedirectURL: cfg.RedirectURL, Endpoint: provider.Endpoint(),
        Scopes: cfg.Scopes,
    }
    return &OIDCProvider{provider, verifier, oauthCfg}, nil
}

func (p *OIDCProvider) Exchange(ctx context.Context, code, nonce string) (*domain.OIDCTokens, error) {
    // 1. Code → OAuth2 Token
    token, err := p.oauth.Exchange(ctx, code)
    // 2. id_token 抽出
    rawIDToken, ok := token.Extra("id_token").(string)
    // 3. 署名検証
    idToken, err := p.verifier.Verify(ctx, rawIDToken)
    // 4. Nonce 検証
    if idToken.Nonce != nonce { return nil, domain.ErrInvalidNonce }
    // 5. Claims 抽出
    var claims struct { Sub, Email, Name string }
    idToken.Claims(&claims)
    return &domain.OIDCTokens{...}, nil
}
```

**検証チェーン:**
1. Authorization Code → Token Exchange
2. ID Token 署名検証 (JWKS)
3. Issuer, Audience, Expiration 検証 (go-oidc 自動)
4. Nonce 検証 (リプレイ攻撃防止)

---

## Auth エラー定義

```go
var (
    ErrSessionNotFound   = errors.New("session not found")
    ErrSessionExpired    = errors.New("session expired")
    ErrInvalidState      = errors.New("invalid state parameter")
    ErrInvalidNonce      = errors.New("invalid nonce")
    ErrUnauthenticated   = errors.New("unauthenticated")
    ErrOIDCNotConfigured = errors.New("OIDC provider not configured")
)
```

---

## 環境変数

| 変数名 | デフォルト | 説明 |
|--------|-----------|------|
| `OIDC_ISSUER_URL` | (なし) | OIDC プロバイダーの Issuer URL |
| `OIDC_CLIENT_ID` | (なし) | OAuth2 Client ID |
| `OIDC_CLIENT_SECRET` | (なし) | OAuth2 Client Secret |
| `OIDC_REDIRECT_URL` | `http://localhost:8080/auth/callback` | コールバック URL |
| `OIDC_SCOPES` | `openid,profile,email` | スコープ (カンマ区切り) |
| `AUTH_FRONTEND_URL` | `http://localhost:5173` | 認証後リダイレクト先 |
| `AUTH_COOKIE_SECURE` | `false` | Cookie Secure 属性 |
