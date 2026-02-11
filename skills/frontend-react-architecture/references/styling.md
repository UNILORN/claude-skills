# スタイリングとテーマ

Panda CSS + Park UI によるゼロランタイム CSS、レシピ、デザイントークン、ダークモード。

---

## 1. UI スタック構成

```
Panda CSS           ← ゼロランタイム CSS-in-JS (ビルド時に CSS 生成)
  ↑
Ark UI (@ark-ui/react)  ← Headless UI コンポーネント
  ↑
Park UI (@park-ui)  ← Ark UI + Panda CSS のスタイル付きコンポーネント
```

**import パス:**
```tsx
// レイアウトコンポーネント (Panda CSS 生成)
import { VStack, HStack, Grid, GridItem, Center, Container } from "styled-system/jsx";

// UI コンポーネント (Park UI ベース)
import { Button, Input, Field, Card, Alert, Heading, Text, Spinner } from "~/components/ui";
```

---

## 2. Panda CSS 設定 (`panda.config.ts`)

```typescript
import { defineConfig } from "@pandacss/dev";
import { createPreset } from "@park-ui/panda-preset";
import neutral from "@park-ui/panda-preset/colors/neutral";
import { recipes, slotRecipes } from "./src/theme/recipes";
import { borderWidths, brand, key, radii, semanticColors, shadows, spacing, textStyles } from "./src/theme/tokens";

export default defineConfig({
  preflight: true,
  presets: [
    "@pandacss/preset-base",
    createPreset({ accentColor: neutral, grayColor: neutral, radius: "md" }),
  ],
  include: ["./src/**/*.{ts,tsx}"],
  outdir: "styled-system",
  jsxFramework: "react",
  conditions: {
    extend: {
      dark: ".dark &",
      light: ".light &",
    },
  },
  globalCss: {
    html: {
      colorScheme: "light",
      _dark: { colorScheme: "dark" },
    },
    "*": {
      transition: "background-color 0.2s ease, color 0.2s ease, border-color 0.2s ease",
    },
  },
  theme: {
    extend: {
      recipes,
      slotRecipes,
      tokens: { colors: { brand, key }, spacing, radii, borderWidths, shadows },
      textStyles,
      semanticTokens: { colors: semanticColors },
    },
  },
});
```

**ポイント:**
- `outdir: "styled-system"` — 生成先 (gitignore)
- `jsxFramework: "react"` — JSX コンポーネント (`VStack` 等) を生成
- カスタム conditions (`dark`/`light`) でクラスベースのダークモード
- テーマ拡張: カスタムレシピ + トークン

---

## 3. UI コンポーネント (`src/components/ui/`)

### レシピベースコンポーネント

```tsx
// src/components/ui/button.tsx
"use client";
import { ark } from "@ark-ui/react/factory";
import { styled } from "styled-system/jsx";
import { button } from "styled-system/recipes";

const BaseButton = styled(ark.button, button);

export const Button = forwardRef<HTMLButtonElement, ButtonProps>(
  function Button(props, ref) {
    const { loading, loadingText, children, spinner, spinnerPlacement, ...rest } = props;
    return (
      <BaseButton
        type="button"
        ref={ref}
        {...rest}
        data-loading={loading ? "" : undefined}
        disabled={loading || rest.disabled}
      >
        {!props.asChild && loading ? (
          <Loader spinner={spinner} text={loadingText} spinnerPlacement={spinnerPlacement}>
            {children}
          </Loader>
        ) : (
          children
        )}
      </BaseButton>
    );
  },
);
```

**パターン:**
- `styled(ark.{element}, {recipe})` — Headless コンポーネント + レシピ
- `forwardRef` で ref 伝播
- `loading` prop でローディング状態を制御

### Slot Recipe コンポーネント (複合コンポーネント)

```tsx
// src/components/ui/card.tsx
"use client";
import { ark } from "@ark-ui/react/factory";
import { createStyleContext } from "styled-system/jsx";
import { card } from "styled-system/recipes";

const { withProvider, withContext } = createStyleContext(card);

export const Root = withProvider(ark.div, "root");
export const Header = withContext(ark.div, "header");
export const Body = withContext(ark.div, "body");
export const Footer = withContext(ark.h3, "footer");
export const Title = withContext(ark.h3, "title");
export const Description = withContext(ark.div, "description");
```

**使用例:**
```tsx
<Card.Root>
  <Card.Header><Card.Title>Title</Card.Title></Card.Header>
  <Card.Body>Content</Card.Body>
  <Card.Footer>Footer</Card.Footer>
</Card.Root>

<Alert.Root status="error">
  <Alert.Indicator />
  <Alert.Content>
    <Alert.Description>Error message</Alert.Description>
  </Alert.Content>
</Alert.Root>

<Field.Root required>
  <Field.Label>Name</Field.Label>
  <Input type="text" />
  <Field.ErrorText>Required</Field.ErrorText>
</Field.Root>
```

### バレルエクスポート

```typescript
// src/components/ui/index.ts
export { Button, ButtonGroup, type ButtonProps } from "./button";
export { Input, type InputProps } from "./input";
export * as Card from "./card";
export * as Alert from "./alert";
export * as Field from "./field";
export { Heading, type HeadingProps } from "./heading";
export { Text, type TextProps } from "./text";
export { Spinner, type SpinnerProps } from "./spinner";
export { ThemeToggle, type ThemeToggleProps } from "./theme-toggle";
// ...
```

**規約:**
- 単一コンポーネント: `export { Component }` — `<Button />`
- 複合コンポーネント: `export * as Namespace` — `<Card.Root />`

---

## 4. レシピ定義 (`src/theme/recipes/`)

### 通常レシピ

```typescript
// src/theme/recipes/button.ts
import { defineRecipe } from "@pandacss/dev";

export const button = defineRecipe({
  className: "button",
  base: { /* 基本スタイル */ },
  variants: {
    variant: {
      solid: { /* ... */ },
      surface: { /* ... */ },
      outline: { /* ... */ },
      plain: { /* ... */ },
    },
    size: {
      "2xs": { /* ... */ },
      sm: { /* ... */ },
      md: { /* ... */ },
      lg: { /* ... */ },
    },
  },
  defaultVariants: {
    variant: "solid",
    size: "md",
  },
});
```

### Slot レシピ (複合コンポーネント用)

```typescript
// src/theme/recipes/card.ts
import { defineSlotRecipe } from "@pandacss/dev";

export const card = defineSlotRecipe({
  className: "card",
  slots: ["root", "header", "body", "footer", "title", "description"],
  base: {
    root: { /* ... */ },
    body: { /* ... */ },
    // 各 slot のスタイル
  },
  variants: {
    variant: {
      elevated: { root: { /* ... */ } },
      outline: { root: { /* ... */ } },
      subtle: { root: { /* ... */ } },
    },
  },
  defaultVariants: { variant: "outline" },
});
```

### レシピの登録

```typescript
// src/theme/recipes/index.ts
export const recipes = {
  button, group, heading, input, spinner, text, absoluteCenter,
};

export const slotRecipes = {
  alert, card, field,
};
```

`panda.config.ts` の `theme.extend.recipes` / `theme.extend.slotRecipes` に登録。

### レシピ追加手順

1. `src/theme/recipes/{recipe-name}.ts` を作成
2. `src/theme/recipes/index.ts` に追加
3. `pnpm panda codegen` で再生成 (dev 時は自動)

---

## 5. デザイントークン (`src/theme/tokens/`)

### カラー

```typescript
// src/theme/tokens/colors.ts
export const brand = {
  10: { value: "#e8f0fe" },
  // ... 10-100 のグラデーション
  100: { value: "#0b1e3b" },
};

export const key = {
  red: {
    dim: { value: "..." },
    DEFAULT: { value: "..." },
    bright: { value: "..." },
  },
  green: { /* ... */ },
  blue: { /* ... */ },
  yellow: { /* ... */ },
  orange: { /* ... */ },
};
```

### セマンティックカラー (ライト/ダーク対応)

```typescript
// src/theme/tokens/semantic.ts
export const semanticColors = {
  surface: {
    DEFAULT: { value: { base: "{colors.white}", _dark: "{colors.neutral.950}" } },
    secondary: { value: { base: "{colors.neutral.50}", _dark: "{colors.neutral.900}" } },
  },
  onSurface: {
    DEFAULT: { value: { base: "{colors.neutral.950}", _dark: "{colors.white}" } },
  },
  border: {
    DEFAULT: { value: { base: "{colors.neutral.200}", _dark: "{colors.neutral.800}" } },
  },
};
```

### テキストスタイル

```typescript
// src/theme/tokens/typography.ts
export const textStyles = {
  headline: {
    sm: { value: { fontSize: "24px", fontWeight: "700", lineHeight: "1.3" } },
    md: { value: { fontSize: "28px", fontWeight: "700", lineHeight: "1.3" } },
    lg: { value: { fontSize: "32px", fontWeight: "700", lineHeight: "1.2" } },
  },
  body: {
    sm: { value: { fontSize: "14px", fontWeight: "400", lineHeight: "1.5" } },
    md: { value: { fontSize: "16px", fontWeight: "400", lineHeight: "1.5" } },
  },
  // ... title, label, caption
};
```

---

## 6. ダークモード

### テーマフラッシュ防止 (`index.html`)

```html
<script>
  (function() {
    const stored = localStorage.getItem('theme');
    const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
    const theme = stored === 'dark' || (stored === 'system' && prefersDark)
      || (!stored && prefersDark) ? 'dark' : 'light';
    document.documentElement.classList.add(theme);
  })();
</script>
```

### ThemeProvider

```tsx
// src/lib/theme/theme-context.tsx
type Theme = "light" | "dark" | "system";

export function ThemeProvider({ children }: { children: ReactNode }) {
  const [theme, setThemeState] = useState<Theme>(getStoredTheme);
  const [resolvedTheme, setResolvedTheme] = useState<"light" | "dark">(...);

  // theme 変更時に document class を更新
  useEffect(() => {
    const resolved = theme === "system" ? getSystemTheme() : theme;
    setResolvedTheme(resolved);
    document.documentElement.classList.remove("light", "dark");
    document.documentElement.classList.add(resolved);
  }, [theme]);

  // system モード時のメディアクエリ監視
  useEffect(() => {
    if (theme !== "system") return;
    const mediaQuery = window.matchMedia("(prefers-color-scheme: dark)");
    const handler = (e: MediaQueryListEvent) => { /* ... */ };
    mediaQuery.addEventListener("change", handler);
    return () => mediaQuery.removeEventListener("change", handler);
  }, [theme]);

  const setTheme = (newTheme: Theme) => {
    setThemeState(newTheme);
    localStorage.setItem("theme", newTheme);
  };

  return <ThemeContext.Provider value={{ theme, resolvedTheme, setTheme }}>{children}</ThemeContext.Provider>;
}

export function useTheme() { /* ... */ }
```

### ThemeToggle

```tsx
// src/components/ui/theme-toggle.tsx
import { MoonIcon, SunIcon } from "lucide-react";
import { useTheme } from "~/lib/theme";
import { Button } from "./button";

export function ThemeToggle() {
  const { resolvedTheme, setTheme } = useTheme();

  return (
    <Button
      variant="ghost"
      size="sm"
      onClick={() => setTheme(resolvedTheme === "dark" ? "light" : "dark")}
      aria-label={resolvedTheme === "dark" ? "Switch to light mode" : "Switch to dark mode"}
    >
      {resolvedTheme === "dark" ? <SunIcon size={20} /> : <MoonIcon size={20} />}
    </Button>
  );
}
```

**ダークモード仕組み:**
1. `index.html` の IIFE で初期クラス設定 (フラッシュ防止)
2. `ThemeProvider` が localStorage とシステム設定を管理
3. `document.documentElement.classList` に `dark`/`light` を設定
4. Panda CSS の `_dark` / `_light` 条件で自動切替
5. `ThemeToggle` でユーザー操作

---

## 7. グローバルスタイル

```css
/* src/styles.css */
@layer reset, base, tokens, recipes, utilities;

:root {
  color-scheme: light;
  background-color: rgb(242 246 249);
  color: rgb(23 26 28);
}

.dark {
  color-scheme: dark;
  background-color: rgb(15 18 20);
  color: #ffffff;
}
```

**CSS Layers 規約 (Panda CSS):**
- `reset` — ブラウザリセット
- `base` — 基本スタイル
- `tokens` — デザイントークン
- `recipes` — コンポーネントレシピ
- `utilities` — ユーティリティクラス (最高優先度)
