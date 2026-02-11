# ツールチェーン

Vite、TypeScript、Storybook、Biome、Docker の設定と使用方法。

---

## 1. Vite 設定

```typescript
// vite.config.ts
import { resolve } from "node:path";
import { TanStackRouterVite } from "@tanstack/router-plugin/vite";
import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

export default defineConfig({
  plugins: [
    TanStackRouterVite({ target: "react", autoCodeSplitting: true }),
    react(),
  ],
  resolve: {
    alias: {
      "~": resolve(__dirname, "./src"),
      "styled-system": resolve(__dirname, "./styled-system"),
    },
  },
});
```

**ポイント:**
- `TanStackRouterVite` — ルートの自動検出 + `routeTree.gen.ts` 自動生成
- `autoCodeSplitting: true` — ルートごとの自動コード分割
- パスエイリアス: `~` → `src/`, `styled-system` → `styled-system/`

---

## 2. TypeScript 設定

```json
// tsconfig.app.json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "jsx": "react-jsx",
    "strict": true,
    "verbatimModuleSyntax": true,   // import type 必須
    "moduleDetection": "force",
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "erasableSyntaxOnly": true,
    "paths": {
      "~/*": ["./src/*"],
      "styled-system/*": ["./styled-system/*"]
    }
  },
  "include": ["src", "gen", "styled-system"]
}
```

**重要な設定:**
- `verbatimModuleSyntax: true` — 型のみの import は `import type` を使用必須
- `erasableSyntaxOnly: true` — TypeScript 5.9+ の型消去のみモード
- `include` に `gen` と `styled-system` を含める (生成コード)

**import type の使い分け:**
```tsx
// 型のみ → import type
import type { User } from "../../../../gen/user/v1/user_pb.ts";
import type { Meta, StoryObj } from "@storybook/react";

// 値も使う → import
import { UserSchema } from "../../../../gen/user/v1/user_pb.ts";
import { createClient } from "@connectrpc/connect";
```

---

## 3. Storybook 設定

### メイン設定

```typescript
// .storybook/main.ts
import { resolve } from "node:path";
import type { StorybookConfig } from "@storybook/react-vite";
import { mergeConfig } from "vite";

const config: StorybookConfig = {
  stories: ["../src/**/*.stories.@(ts|tsx)"],
  addons: ["@storybook/addon-essentials"],
  framework: {
    name: "@storybook/react-vite",
    options: {},
  },
  viteFinal: (config) => {
    return mergeConfig(config, {
      resolve: {
        alias: {
          "~": resolve(__dirname, "../src"),
          "styled-system": resolve(__dirname, "../styled-system"),
        },
      },
    });
  },
};
```

**ポイント:**
- `@storybook/react-vite` — Vite ベースのビルド
- `viteFinal` で Vite エイリアスを追加 (本体の `vite.config.ts` と同じ)
- Storybook 8 パッケージは全て `@^8` で統一

### プレビュー設定

```typescript
// .storybook/preview.ts
import type { Preview } from "@storybook/react";
import "../src/styles.css";  // グローバルスタイルを読み込み

const preview: Preview = {
  parameters: {
    controls: {
      matchers: {
        color: /(background|color)$/i,
        date: /Date$/i,
      },
    },
  },
};
```

### コマンド

```bash
pnpm --filter frontend-react storybook        # Storybook 開発 (port 6006)
pnpm --filter frontend-react build-storybook   # Storybook ビルド
```

**注意:** Storybook 起動前に `panda codegen` が自動実行される (scripts で設定済み)

---

## 4. Biome (Linter + Formatter)

```bash
pnpm --filter frontend-react lint      # Lint チェック
pnpm --filter frontend-react lint:fix  # 自動修正
pnpm --filter frontend-react format    # フォーマット
```

**ESLint も併用:**
```bash
pnpm --filter frontend-react lint:eslint  # ESLint (react-hooks, react-refresh)
```

---

## 5. スクリプト一覧

| コマンド | 説明 |
|---------|------|
| `pnpm --filter frontend-react dev` | Vite dev + Panda CSS watch |
| `pnpm --filter frontend-react build` | Panda codegen → tsc → Vite build |
| `pnpm --filter frontend-react preview` | ビルド結果のプレビュー |
| `pnpm --filter frontend-react typecheck` | TypeScript 型チェック |
| `pnpm --filter frontend-react lint` | Biome lint |
| `pnpm --filter frontend-react lint:fix` | Biome 自動修正 |
| `pnpm --filter frontend-react storybook` | Storybook 開発 |
| `pnpm --filter frontend-react build-storybook` | Storybook ビルド |

**ルートからの省略形:**
```bash
pnpm dev              # backend + frontend 同時起動
pnpm dev:frontend     # frontend のみ (localhost:5173)
pnpm buf:generate     # Proto → Go + TypeScript 生成
```

---

## 6. PostCSS 設定

```javascript
// postcss.config.cjs
module.exports = {
  plugins: {
    "@pandacss/dev/postcss": {},
  },
};
```

Panda CSS の PostCSS プラグインで CSS 生成を統合。

---

## 7. Docker ビルド

```dockerfile
# Dockerfile (frontend-react)
# Vite ビルド → Nginx で静的配信
```

```nginx
# nginx.conf
# SPA 対応: 全パスを index.html にフォールバック
```

---

## 8. 自動生成ファイル (gitignore)

| ファイル/ディレクトリ | 生成元 | コマンド |
|---------------------|--------|---------|
| `gen/` | Proto 定義 | `pnpm buf:generate` |
| `styled-system/` | Panda CSS 設定 | `pnpm panda codegen` |
| `src/routeTree.gen.ts` | TanStack Router routes | `pnpm dev` (自動) |

---

## 9. 既知の注意点

### Storybook 8 バージョン管理

- Storybook 関連パッケージは全て `@^8` で統一
- `storybook` CLI がデフォルトで最新 (v10) をインストールする場合がある → `@^8` を明示指定
- Vite 7 との peer dep 警告は出るが動作に問題なし

### @bufbuild/protobuf v2

- `GenMessage` は `@bufbuild/protobuf/codegenv2` サブパスにある (メインエクスポートではない)
- 汎用ユーティリティには `DescMessage`, `MessageShape`, `MessageInitShape` を使用 (メインエクスポート)
- テストファクトリは `create(schema, init)` で Proto メッセージを生成

### verbatimModuleSyntax

- 型のみの import は必ず `import type { ... }` を使用
- 値と型を混在させる場合は分けて書く:
  ```tsx
  import type { User } from "./user_pb.ts";
  import { UserSchema } from "./user_pb.ts";
  ```
