# コンポーネントパターン

Container/Presentational パターン、API フック、Feature モジュール構成。

---

## 1. Feature モジュール構成

```
src/features/{feature}/
├── api/
│   ├── client.ts                  # ConnectRPC クライアント
│   ├── useCreate{Feature}.ts      # 作成フック
│   └── useGet{Feature}.ts         # 取得フック
├── components/
│   ├── {Feature}Form.tsx          # Presentational (フォーム)
│   ├── {Feature}FormContainer.tsx # Container (API 接続)
│   ├── {Feature}Detail.tsx        # Presentational (詳細表示)
│   ├── {Feature}SearchForm.tsx    # Presentational (検索)
│   └── *.stories.tsx              # Storybook stories
├── testing/
│   └── factories.ts               # Proto テストファクトリ
└── index.ts                        # Public exports
```

---

## 2. API レイヤー

### ConnectRPC クライアント

```typescript
// src/features/user/api/client.ts
import { createClient } from "@connectrpc/connect";
import { UserService } from "../../../../gen/user/v1/user_pb.ts";
import { transport } from "../../../shared/api/transport.ts";

export const userClient = createClient(UserService, transport);
```

**パターン:**
- `gen/` の Proto 生成サービスから `createClient` でクライアント作成
- `shared/api/transport.ts` を共有 (credentials 付き)
- Feature ごとに `{feature}Client` を作成

### 共有 Transport

```typescript
// src/shared/api/transport.ts
import { createConnectTransport } from "@connectrpc/connect-web";

const baseUrl = import.meta.env.VITE_API_BASE_URL ?? "http://localhost:8080";

export const transport = createConnectTransport({
  baseUrl,
  fetch: (input, init) => fetch(input, { ...init, credentials: "include" }),
});
```

**ポイント:**
- `credentials: "include"` でセッション Cookie を自動送信
- `VITE_API_BASE_URL` 環境変数で API ベース URL を設定可能

### API フック (Per-Action Hook)

```typescript
// src/features/user/api/useCreateUser.ts
import { useCallback, useState } from "react";
import type { User } from "../../../../gen/user/v1/user_pb.ts";
import { userClient } from "./client.ts";

export interface UseCreateUserResult {
  execute: (name: string, email: string) => Promise<User | undefined>;
  data: User | undefined;
  loading: boolean;
  error: string | null;
  reset: () => void;
}

export function useCreateUser(): UseCreateUserResult {
  const [data, setData] = useState<User | undefined>();
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const reset = useCallback(() => {
    setData(undefined);
    setError(null);
  }, []);

  const execute = useCallback(async (name: string, email: string) => {
    setLoading(true);
    setError(null);
    try {
      const res = await userClient.createUser({ name, email });
      setData(res.user);
      return res.user;
    } catch (err) {
      const message = err instanceof Error ? err.message : "Failed to create user";
      setError(message);
      return undefined;
    } finally {
      setLoading(false);
    }
  }, []);

  return { execute, data, loading, error, reset };
}
```

**API フック規約:**
- 1アクション = 1フック (`useCreateUser`, `useGetUser`)
- 戻り値: `{ execute, data, loading, error, reset }`
- `execute` は `useCallback` でメモ化
- エラーは `string | null` で管理 (Error オブジェクトから message 抽出)
- Proto の型 (`User`) を `import type` で取得

---

## 3. Presentational コンポーネント

Props のみに依存。API 呼び出し・外部状態を持たない。

### フォームコンポーネント

```tsx
// src/features/user/components/CreateUserForm.tsx
import { useState } from "react";
import { VStack } from "styled-system/jsx";
import { Alert, Button, Field, Heading, Input } from "~/components/ui";

export interface CreateUserFormProps {
  loading: boolean;
  error: string | null;
  onSubmit: (name: string, email: string) => void;
}

export function CreateUserForm({ loading, error, onSubmit }: CreateUserFormProps) {
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    onSubmit(name, email);
    setName("");
    setEmail("");
  };

  return (
    <form onSubmit={handleSubmit}>
      <VStack gap="4" alignItems="stretch">
        <Heading as="h2" textStyle="xl">Create User</Heading>
        <Field.Root required>
          <Field.Label>Name</Field.Label>
          <Input type="text" value={name} onChange={(e) => setName(e.target.value)} />
        </Field.Root>
        <Field.Root required>
          <Field.Label>Email</Field.Label>
          <Input type="email" value={email} onChange={(e) => setEmail(e.target.value)} />
        </Field.Root>
        <Button type="submit" loading={loading}>Create User</Button>
        {error && (
          <Alert.Root status="error">
            <Alert.Indicator />
            <Alert.Content>
              <Alert.Description>{error}</Alert.Description>
            </Alert.Content>
          </Alert.Root>
        )}
      </VStack>
    </form>
  );
}
```

### 詳細表示コンポーネント

```tsx
// src/features/user/components/UserDetail.tsx
import { VStack } from "styled-system/jsx";
import { Card, Text } from "~/components/ui";

export interface UserDetailProps {
  id: string;
  name: string;
  email: string;
}

export function UserDetail({ id, name, email }: UserDetailProps) {
  return (
    <Card.Root mt="4">
      <Card.Body>
        <VStack gap="2" alignItems="stretch">
          <Text><strong>ID:</strong> {id}</Text>
          <Text><strong>Name:</strong> {name}</Text>
          <Text><strong>Email:</strong> {email}</Text>
        </VStack>
      </Card.Body>
    </Card.Root>
  );
}
```

**Presentational 規約:**
- Props のみ依存 (`loading`, `error`, `onSubmit` など)
- API クライアントを import しない
- `styled-system/jsx` と `~/components/ui` のみを使用
- フォーム状態 (`useState`) は OK (ローカル UI 状態)
- Storybook 対象

---

## 4. Container コンポーネント

API フックと Presentational をつなぐ。

```tsx
// src/features/user/components/CreateUserFormContainer.tsx
import { useCreateUser } from "../api/useCreateUser.ts";
import { CreateUserForm } from "./CreateUserForm.tsx";

export interface CreateUserFormContainerProps {
  onCreated?: (user: { id: string; name: string; email: string }) => void;
}

export function CreateUserFormContainer({ onCreated }: CreateUserFormContainerProps) {
  const { execute, loading, error } = useCreateUser();

  const handleSubmit = async (name: string, email: string) => {
    const user = await execute(name, email);
    if (user && onCreated) {
      onCreated({ id: user.id, name: user.name, email: user.email });
    }
  };

  return <CreateUserForm loading={loading} error={error} onSubmit={handleSubmit} />;
}
```

**Container 規約:**
- API フックを使用してデータ取得/操作
- Presentational コンポーネントに props をマッピング
- コールバック props (`onCreated`) でルート側にイベント通知
- Storybook 対象外

---

## 5. バレルエクスポート

```typescript
// src/features/user/index.ts
export type { CreateUserFormProps } from "./components/CreateUserForm.tsx";
export { CreateUserForm } from "./components/CreateUserForm.tsx";
export { CreateUserFormContainer } from "./components/CreateUserFormContainer.tsx";
export type { UserDetailProps } from "./components/UserDetail.tsx";
export { UserDetail } from "./components/UserDetail.tsx";
export type { UserSearchFormProps } from "./components/UserSearchForm.tsx";
export { UserSearchForm } from "./components/UserSearchForm.tsx";
```

**規約:**
- `verbatimModuleSyntax` のため `export type` と `export` を分離
- 型は `export type { ... }` で re-export
- 値は `export { ... }` で re-export

---

## 6. テストファクトリ

```typescript
// src/shared/testing/protoHelpers.ts
import type { DescMessage, MessageInitShape, MessageShape } from "@bufbuild/protobuf";
import { create } from "@bufbuild/protobuf";

export function createFactory<Desc extends DescMessage>(
  schema: Desc,
  defaults: MessageInitShape<Desc>,
) {
  return (overrides?: Partial<MessageInitShape<Desc>>): MessageShape<Desc> => {
    return create(schema, { ...defaults, ...overrides } as MessageInitShape<Desc>);
  };
}
```

```typescript
// src/features/user/testing/factories.ts
import { UserSchema } from "../../../../gen/user/v1/user_pb.ts";
import { createFactory } from "../../../shared/testing/protoHelpers.ts";

export const buildUser = createFactory(UserSchema, {
  id: "test-id-001",
  name: "Test User",
  email: "test@example.com",
});

// 使用例
const user = buildUser();                              // デフォルト値
const customUser = buildUser({ name: "Custom User" }); // 部分上書き
```

**Proto ファクトリ規約:**
- `@bufbuild/protobuf` v2 の `DescMessage`, `MessageShape`, `MessageInitShape` を使用
- `GenMessage` は使わない (v2 では `codegenv2` サブパスにある)
- Feature ごとに `testing/factories.ts` を作成
- `build{Entity}` 命名規則

---

## 7. Storybook Stories

```tsx
// src/features/user/components/CreateUserForm.stories.tsx
import type { Meta, StoryObj } from "@storybook/react";
import { fn } from "@storybook/test";
import { CreateUserForm } from "./CreateUserForm.tsx";

const meta = {
  title: "user/CreateUserForm",
  component: CreateUserForm,
  args: {
    onSubmit: fn(),
  },
} satisfies Meta<typeof CreateUserForm>;

export default meta;
type Story = StoryObj<typeof meta>;

export const Default: Story = {
  args: { loading: false, error: null },
};

export const Loading: Story = {
  args: { loading: true, error: null },
};

export const WithError: Story = {
  args: { loading: false, error: "Email already exists" },
};
```

**Storybook 規約:**
- Presentational コンポーネントのみ (Container は対象外)
- `fn()` で `@storybook/test` のモックコールバック
- `satisfies Meta<typeof Component>` で型安全
- タイトル: `{feature}/{ComponentName}`
- 最低限の Story: `Default`, `Loading`, `WithError`
