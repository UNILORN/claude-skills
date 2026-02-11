# ルーティングと認証

TanStack Router ファイルベースルーティング、認証ガード、ナビゲーション。

---

## 1. エントリーポイント

```tsx
// src/main.tsx
import { createRouter, RouterProvider } from "@tanstack/react-router";
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { ThemeProvider } from "./lib/theme";
import { AuthProvider } from "./shared/auth";
import "./styles.css";
import { routeTree } from "./routeTree.gen";

const router = createRouter({ routeTree });

// 型安全ルーティングの登録
declare module "@tanstack/react-router" {
  interface Register {
    router: typeof router;
  }
}

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <ThemeProvider>
      <AuthProvider>
        <RouterProvider router={router} />
      </AuthProvider>
    </ThemeProvider>
  </StrictMode>,
);
```

**ポイント:**
- `routeTree.gen.ts` は TanStack Router プラグインが自動生成 (gitignore)
- `declare module` で router 型を登録 → 型安全ナビゲーション
- Provider 順序: Theme → Auth → Router

---

## 2. ルートレイアウト (`__root.tsx`)

```tsx
// src/routes/__root.tsx
import { createRootRoute, Outlet } from "@tanstack/react-router";
import { Center, Container, HStack } from "styled-system/jsx";
import { Spinner } from "~/components/ui/spinner";
import { ThemeToggle } from "~/components/ui/theme-toggle";
import { UserMenu, useAuth } from "~/shared/auth";

const API_BASE = import.meta.env.VITE_API_BASE_URL ?? "http://localhost:8080";

export const Route = createRootRoute({
  component: RootLayout,
});

function RootLayout() {
  const { isLoading, isAuthenticated, user, logout } = useAuth();

  // 認証ロード中
  if (isLoading) {
    return (
      <Center h="100vh">
        <Spinner />
      </Center>
    );
  }

  // 未認証 → バックエンドの /auth/login へリダイレクト
  if (!isAuthenticated) {
    window.location.href = `${API_BASE}/auth/login`;
    return null;
  }

  // 認証済み → レイアウト表示
  return (
    <Container maxW="4xl" py="8">
      <HStack justify="flex-end" gap="2" mb="4">
        <ThemeToggle />
        {user && <UserMenu user={user} onLogout={() => void logout()} />}
      </HStack>
      <Outlet />
    </Container>
  );
}
```

**認証ガードパターン:**
1. `isLoading` 中は Spinner 表示
2. 未認証時はバックエンドの OIDC ログインエンドポイントへ `window.location.href` でリダイレクト
3. 認証済みなら `<Outlet />` で子ルートを描画

---

## 3. ルート定義

### リダイレクト (`/` → `/users`)

```tsx
// src/routes/index.tsx
import { createFileRoute, redirect } from "@tanstack/react-router";

export const Route = createFileRoute("/")({
  beforeLoad: () => {
    throw redirect({ to: "/users" });
  },
});
```

### 一覧/作成ページ

```tsx
// src/routes/users/index.tsx
import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { Grid, GridItem, VStack } from "styled-system/jsx";
import { Heading } from "~/components/ui";
import { CreateUserFormContainer } from "../../features/user/components/CreateUserFormContainer.tsx";
import { UserSearchForm } from "../../features/user/components/UserSearchForm.tsx";

export const Route = createFileRoute("/users/")({
  component: UsersPage,
});

function UsersPage() {
  const navigate = useNavigate();

  const handleCreated = (user: { id: string }) => {
    void navigate({ to: "/users/$userId", params: { userId: user.id } });
  };

  const handleSearch = (id: string) => {
    void navigate({ to: "/users/$userId", params: { userId: id } });
  };

  return (
    <VStack gap="6" alignItems="stretch">
      <Heading as="h1" textStyle="3xl">User Management</Heading>
      <Grid columns={{ base: 1, md: 2 }} gap="8">
        <GridItem>
          <CreateUserFormContainer onCreated={handleCreated} />
        </GridItem>
        <GridItem>
          <UserSearchForm loading={false} error={null} onSearch={handleSearch} />
        </GridItem>
      </Grid>
    </VStack>
  );
}
```

### 詳細ページ (動的パラメータ)

```tsx
// src/routes/users/$userId.tsx
import { createFileRoute, Link } from "@tanstack/react-router";
import { useEffect } from "react";
import { HStack, VStack } from "styled-system/jsx";
import { Alert, Button, Heading, Spinner, Text } from "~/components/ui";
import { useGetUser } from "../../features/user/api/useGetUser.ts";
import { UserDetail } from "../../features/user/components/UserDetail.tsx";

export const Route = createFileRoute("/users/$userId")({
  component: UserDetailPage,
});

function UserDetailPage() {
  const { userId } = Route.useParams();  // 型安全パラメータ取得
  const { execute, data, loading, error } = useGetUser();

  useEffect(() => {
    void execute(userId);
  }, [execute, userId]);

  return (
    <VStack gap="4" alignItems="stretch">
      <Heading as="h1" textStyle="3xl">User Detail</Heading>
      <Button asChild variant="plain" alignSelf="flex-start">
        <Link to="/users">&larr; Back to Users</Link>
      </Button>
      {loading && (
        <HStack gap="2">
          <Spinner />
          <Text>Loading...</Text>
        </HStack>
      )}
      {error && (
        <Alert.Root status="error">
          <Alert.Indicator />
          <Alert.Content>
            <Alert.Description>{error}</Alert.Description>
          </Alert.Content>
        </Alert.Root>
      )}
      {data && <UserDetail id={data.id} name={data.name} email={data.email} />}
    </VStack>
  );
}
```

---

## 4. ルーティング規約

### ファイル名 → URL マッピング

| ファイル | URL | 説明 |
|---------|-----|------|
| `routes/__root.tsx` | — | ルートレイアウト |
| `routes/index.tsx` | `/` | トップページ |
| `routes/users/index.tsx` | `/users` | 一覧ページ |
| `routes/users/$userId.tsx` | `/users/:userId` | 詳細ページ |

### 型安全ナビゲーション

```tsx
// パラメータ付きナビゲーション
navigate({ to: "/users/$userId", params: { userId: user.id } });

// ルートパラメータ取得
const { userId } = Route.useParams();

// Link コンポーネント
<Link to="/users">Back to Users</Link>
<Link to="/users/$userId" params={{ userId: id }}>View User</Link>
```

### 新ルート追加時

1. `src/routes/{feature}s/index.tsx` を作成
2. `src/routes/{feature}s/${feature}Id.tsx` を作成 (詳細ページ)
3. `pnpm dev` で `routeTree.gen.ts` が自動再生成

---

## 5. 認証システム

### AuthContext

```tsx
// src/shared/auth/AuthContext.tsx
export interface AuthUser {
  subject: string;
  email: string;
  name: string;
}

export interface AuthContextValue {
  user: AuthUser | null;
  isLoading: boolean;
  isAuthenticated: boolean;
  logout: () => Promise<void>;
}

export const AuthContext = createContext<AuthContextValue | null>(null);

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) {
    throw new Error("useAuth must be used within an AuthProvider");
  }
  return ctx;
}
```

### AuthProvider

```tsx
// src/shared/auth/AuthProvider.tsx
const API_BASE = import.meta.env.VITE_API_BASE_URL ?? "http://localhost:8080";

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<AuthUser | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  // マウント時に /auth/me でセッション確認
  useEffect(() => {
    fetch(`${API_BASE}/auth/me`, { credentials: "include" })
      .then((res) => (res.ok ? res.json() : null))
      .then((data: AuthUser | null) => setUser(data))
      .catch(() => setUser(null))
      .finally(() => setIsLoading(false));
  }, []);

  // ログアウト: セッション破棄 → 再認証ページへリダイレクト
  const logout = useCallback(async () => {
    await fetch(`${API_BASE}/auth/logout`, {
      method: "POST",
      credentials: "include",
    });
    // prompt=login で OIDC プロバイダーの再認証を強制
    window.location.href = `${API_BASE}/auth/login?prompt=login`;
  }, []);

  return (
    <AuthContext value={{ user, isLoading, isAuthenticated: !!user, logout }}>
      {children}
    </AuthContext>
  );
}
```

**認証フロー (フロントエンド視点):**
1. アプリ起動 → `AuthProvider` が `/auth/me` を fetch
2. 200 OK → ユーザー情報をセット → `isAuthenticated: true`
3. 401 → `user: null` → `isAuthenticated: false`
4. `__root.tsx` が未認証を検知 → `/auth/login` へリダイレクト
5. バックエンドの OIDC フロー完了 → Cookie セット → フロントエンドへリダイレクト

### UserMenu

```tsx
// src/shared/auth/UserMenu.tsx
export interface UserMenuProps {
  user: AuthUser;
  onLogout: () => void;
}

export function UserMenu({ user, onLogout }: UserMenuProps) {
  return (
    <HStack justify="flex-end" mb="4">
      <Text fontSize="sm" color="fg.muted">
        {user.name || user.email}
      </Text>
      <Button variant="ghost" size="sm" onClick={onLogout}>
        Logout
      </Button>
    </HStack>
  );
}
```

---

## 6. 環境変数

| 変数名 | デフォルト | 説明 |
|--------|-----------|------|
| `VITE_API_BASE_URL` | `http://localhost:8080` | バックエンド API のベース URL |
