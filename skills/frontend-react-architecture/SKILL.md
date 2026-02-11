---
name: frontend-react-architecture
description: React フロントエンドの実装リファレンス。Container/Presentational パターン、TanStack Router ファイルベースルーティング、ConnectRPC クライアント、Panda CSS + Park UI スタイリング、ダークモード、OIDC 認証連携、Storybook、テストファクトリを網羅。「フロントエンド」「React」「ルーティング」「コンポーネント」「スタイル」「Panda CSS」「Park UI」「Storybook」「API フック」「transport」「認証」「テーマ」「ダークモード」で発動。
---

# Frontend React Architecture Reference

現在のフロントエンド React ソースコードの実装パターンを完全に文書化したスキル。

## Tech Stack

| カテゴリ | 技術 | バージョン |
|---------|------|-----------|
| Framework | React | ^19.2.0 |
| Build | Vite | ^7.3.1 |
| Language | TypeScript | ~5.9.3 |
| Routing | TanStack Router | ^1.159.5 |
| API | ConnectRPC (connect-web) | ^2.1.1 |
| Proto | @bufbuild/protobuf v2 | ^2.11.0 |
| CSS-in-JS | Panda CSS | ^1.8.1 |
| UI Components | Ark UI + Park UI | ^5.31.0 / ^0.43.1 |
| Icons | lucide-react | ^0.563.0 |
| Storybook | Storybook 8 | ^8.6.15 |
| Linter | Biome | ^2.3.14 |

## Directory Structure (実際のコード)

```
packages/frontend-react/
├── .storybook/
│   ├── main.ts                    # Storybook 設定 (Vite alias 含む)
│   └── preview.ts                 # グローバルスタイル読み込み
├── gen/                           # Proto 生成 TypeScript (gitignore)
│   └── {feature}/v1/
│       └── {feature}_pb.ts
├── src/
│   ├── components/
│   │   └── ui/                    # Park UI ベースの共通 UI コンポーネント
│   │       ├── button.tsx
│   │       ├── input.tsx
│   │       ├── field.tsx
│   │       ├── card.tsx
│   │       ├── alert.tsx
│   │       ├── heading.tsx
│   │       ├── text.tsx
│   │       ├── spinner.tsx
│   │       ├── loader.tsx
│   │       ├── theme-toggle.tsx
│   │       └── index.ts           # バレルエクスポート
│   ├── features/                  # Feature モジュール
│   │   └── {feature}/
│   │       ├── api/
│   │       │   ├── client.ts      # ConnectRPC クライアント
│   │       │   ├── useCreate{Feature}.ts
│   │       │   └── useGet{Feature}.ts
│   │       ├── components/
│   │       │   ├── {Feature}Form.tsx           # Presentational
│   │       │   ├── {Feature}FormContainer.tsx  # Container
│   │       │   ├── {Feature}Detail.tsx         # Presentational
│   │       │   └── *.stories.tsx               # Storybook
│   │       ├── testing/
│   │       │   └── factories.ts   # Proto テストファクトリ
│   │       └── index.ts           # Public exports
│   ├── lib/
│   │   └── theme/                 # テーマプロバイダー
│   │       ├── theme-context.tsx
│   │       └── index.ts
│   ├── routes/                    # TanStack Router ファイルベースルーティング
│   │   ├── __root.tsx             # ルートレイアウト (認証ガード)
│   │   ├── index.tsx              # / → /users redirect
│   │   └── {feature}s/
│   │       ├── index.tsx          # 一覧/作成ページ
│   │       └── ${feature}Id.tsx   # 詳細ページ
│   ├── shared/
│   │   ├── api/
│   │   │   └── transport.ts       # ConnectRPC transport (credentials 付き)
│   │   ├── auth/
│   │   │   ├── AuthContext.tsx     # 認証コンテキスト
│   │   │   ├── AuthProvider.tsx    # 認証プロバイダー
│   │   │   ├── UserMenu.tsx       # ユーザーメニュー
│   │   │   └── index.ts
│   │   └── testing/
│   │       └── protoHelpers.ts    # Proto ファクトリヘルパー
│   ├── theme/
│   │   ├── recipes/               # Panda CSS レシピ
│   │   │   ├── button.ts, input.ts, heading.ts, ...
│   │   │   └── index.ts          # recipes + slotRecipes エクスポート
│   │   └── tokens/                # デザイントークン
│   │       ├── colors.ts, typography.ts, spacing.ts, ...
│   │       └── index.ts
│   ├── main.tsx                   # エントリーポイント
│   ├── routeTree.gen.ts           # TanStack Router 自動生成 (gitignore)
│   └── styles.css                 # グローバルスタイル (Panda CSS layers)
├── styled-system/                 # Panda CSS 生成コード (gitignore)
├── panda.config.ts                # Panda CSS 設定
├── vite.config.ts                 # Vite 設定
├── biome.json                     # Biome Lint/Format
├── tsconfig.app.json              # TypeScript 設定
├── index.html                     # HTML テンプレート (テーマプリロード)
├── Dockerfile                     # Docker ビルド
└── nginx.conf                     # Nginx SPA 設定
```

## Provider 階層

```
<StrictMode>
  <ThemeProvider>          ← ダークモード管理
    <AuthProvider>         ← OIDC セッション確認
      <RouterProvider />   ← TanStack Router
    </AuthProvider>
  </ThemeProvider>
</StrictMode>
```

## Detailed References

- **コンポーネントパターン** (Container/Presentational, API フック, Feature 構成): [references/components.md](references/components.md)
- **ルーティングと認証** (TanStack Router, Auth ガード, ナビゲーション): [references/routing-and-auth.md](references/routing-and-auth.md)
- **スタイリングとテーマ** (Panda CSS, Park UI, レシピ, トークン, ダークモード): [references/styling.md](references/styling.md)
- **ツールチェーン** (Vite, TypeScript, Storybook, Biome, Docker): [references/toolchain.md](references/toolchain.md)

## Quick Reference: 新 Feature 追加チェックリスト

1. `pnpm buf:generate` で Proto → TypeScript 生成
2. `src/features/{feature}/api/client.ts` — ConnectRPC クライアント
3. `src/features/{feature}/api/useCreate{Feature}.ts` — Mutation フック
4. `src/features/{feature}/api/useGet{Feature}.ts` — Query フック
5. `src/features/{feature}/components/{Feature}Form.tsx` — Presentational
6. `src/features/{feature}/components/{Feature}FormContainer.tsx` — Container
7. `src/features/{feature}/components/{Feature}Detail.tsx` — Presentational
8. `src/features/{feature}/components/*.stories.tsx` — Storybook
9. `src/features/{feature}/testing/factories.ts` — テストファクトリ
10. `src/features/{feature}/index.ts` — バレルエクスポート
11. `src/routes/{feature}s/index.tsx` — 一覧ページ
12. `src/routes/{feature}s/${feature}Id.tsx` — 詳細ページ
