---
name: codex-subagent-delegation
description: >
  Claude Code でプランを作成後、Codex CLI を使って実装タスクをサブエージェントに委譲。
  非インタラクティブ実行により、長時間タスクをバックグラウンドで自動実行し、Plan-Do分離ワークフローを実現。
  「Codex に任せて」「codex exec」「サブエージェント実行」で発動。
license: MIT
---

# Codex Subagent Delegation

## Overview

このスキルは、Claude Code でプランを作成した後、Codex CLI を使って実装タスクをサブエージェントに委譲するための機能を提供します。

**Plan-Do分離ワークフロー:**

```
┌──────────────────┐
│  Claude Code     │  計画策定フェーズ
│  (Plan Mode)     │  - 要件分析
│                  │  - アーキテクチャ設計
│                  │  - タスク分解
└────────┬─────────┘
         │
         ▼ プラン委譲
┌──────────────────┐
│  Codex CLI       │  実装フェーズ
│  (exec)          │  - コード生成
│                  │  - テスト追加
│                  │  - ドキュメント更新
└────────┬─────────┘
         │
         ▼ 結果報告
┌──────────────────┐
│  Claude Code     │  レビューフェーズ
│                  │  - 変更確認
│                  │  - テスト実行
│                  │  - コミット
└──────────────────┘
```

**主な価値提供:**
- **長時間タスクの自動実行:** ユーザー不在でも実装を継続
- **役割分担の明確化:** 計画策定と実装を分離
- **安全な変更管理:** Git による変更追跡と復元

---

## When to Use

このスキルは以下のシナリオで使用します:

### ✅ 推奨ケース

1. **長時間タスク（30分以上の実装）**
   - 大規模リファクタリング（モジュール分割、パターン適用）
   - 複数ファイルにまたがる機能追加
   - テストスイート全体の更新

2. **プラン後の実装委譲**
   - Claude Code の Plan Mode でプランを作成済み
   - 実装ステップが明確に定義されている
   - 各ステップが独立して検証可能

3. **繰り返し可能なタスク**
   - 複数のモジュールに同じパターンを適用
   - 既存のコード規約に従った実装

### ❌ 避けるべきケース

- プランが曖昧または未定義
- ユーザー入力が必要な対話的タスク
- 本番環境への直接デプロイ
- データベースマイグレーションなどの破壊的操作

---

## Prerequisites

Codex CLI のインストールと認証が必要です。

### インストール確認

```bash
# Codex CLI がインストールされているか確認
which codex

# バージョン確認（認証状態も確認できる）
codex --version
```

### インストール方法

Codex CLI がインストールされていない場合:

```bash
# Homebrew でインストール（推奨）
brew install codex-cli

# または npm でインストール
npm install -g @openai/codex
```

### 認証設定

```bash
# Codex にログイン
codex login

# 認証確認
codex --version  # エラーが出なければ認証成功
```

### Git 環境（推奨）

Codex はどこでも動作しますが、安全性のため Git リポジトリ内での使用を推奨します:

```bash
# Git リポジトリか確認
git rev-parse --git-dir

# Git リポジトリでない場合は初期化
git init
```

---

## Workflow (MVP)

```
┌─────────────────────────────────────────────────────────┐
│ Phase 1: 前提条件チェック                                 │
├─────────────────────────────────────────────────────────┤
│ 1. which codex - インストール確認                         │
│ 2. codex --version - 認証確認                            │
│ 3. git rev-parse --git-dir - Git確認（警告のみ）         │
└─────────────────────────────────────────────────────────┘
              ↓
┌─────────────────────────────────────────────────────────┐
│ Phase 2: プロンプトファイル作成                           │
├─────────────────────────────────────────────────────────┤
│ 1. ユーザーからプラン内容を取得                           │
│ 2. /tmp/codex-prompt-{timestamp}.md に保存               │
│    - タスク説明                                          │
│    - 成功基準                                            │
│    - 制約条件（既存パターンに従う、テスト追加など）        │
└─────────────────────────────────────────────────────────┘
              ↓
┌─────────────────────────────────────────────────────────┐
│ Phase 3: codex exec 実行                                 │
├─────────────────────────────────────────────────────────┤
│ codex exec \                                            │
│   --full-auto \                                         │
│   --output-last-message /tmp/result-{timestamp}.txt \   │
│   -C $(pwd) \                                           │
│   - < /tmp/codex-prompt-{timestamp}.md                  │
└─────────────────────────────────────────────────────────┘
              ↓
┌─────────────────────────────────────────────────────────┐
│ Phase 4: 結果報告                                        │
├─────────────────────────────────────────────────────────┤
│ 1. 終了コードで成功/失敗判定                              │
│ 2. 成功時: git status で変更ファイル表示                 │
│ 3. 失敗時: エラーメッセージ表示                           │
│ 4. クリーンアップ: 一時ファイル削除                       │
└─────────────────────────────────────────────────────────┘
```

---

## Instructions

Claude Code は以下のステップを実行してください:

### Step 1: 環境確認

```bash
# Codex CLI インストール確認
if ! command -v codex &> /dev/null; then
    echo "❌ Codex CLI がインストールされていません"
    echo ""
    echo "インストール方法:"
    echo "  brew install codex-cli"
    echo "または"
    echo "  npm install -g @openai/codex"
    exit 1
fi

# 認証確認
if ! codex --version 2>&1 | grep -q "codex"; then
    echo "❌ Codex CLI の認証が必要です"
    echo ""
    echo "以下を実行してください:"
    echo "  codex login"
    exit 1
fi

# Git 確認（警告のみ）
if ! git rev-parse --git-dir &> /dev/null; then
    echo "⚠️  Git リポジトリではありません（Codexは動作しますが推奨しません）"
fi

echo "✅ 環境確認完了"
```

### Step 2: プロンプトファイル作成

ユーザーから提供されたプラン内容を元に、Codex 用のプロンプトファイルを作成します:

```bash
TIMESTAMP=$(date +%Y%m%d%H%M%S)
PROMPT_FILE="/tmp/codex-prompt-${TIMESTAMP}.md"
RESULT_FILE="/tmp/codex-result-${TIMESTAMP}.txt"

cat > "$PROMPT_FILE" << 'EOF'
# Task: {ユーザーが指定したタスク名}

## Objective
{タスクの目的}

## Plan
{Claude Code で作成したプラン内容}

## Constraints
- Follow existing code patterns in the repository
- Add tests for all new functionality
- Update relevant documentation
- Run tests before completing

## Success Criteria
- All tests pass
- Code follows project linting rules
- Changes are properly documented
EOF

echo "✅ プロンプトファイル作成: $PROMPT_FILE"
```

**プロンプト作成のポイント:**
- タスク名は具体的に（例: "Refactor user.js to async/await"）
- プランは箇条書きで明確に
- 制約条件にプロジェクト固有のルールを追加
- 成功基準は検証可能な形で記述

### Step 3: Codex 実行

```bash
echo "🚀 Codex CLI を実行中..."
echo ""

codex exec \
  --full-auto \
  --output-last-message "$RESULT_FILE" \
  -C "$(pwd)" \
  - < "$PROMPT_FILE"

EXIT_CODE=$?
```

**オプション説明:**
- `--full-auto`: 自動承認モード（workspace-write + on-request approval）
- `--output-last-message`: Codex からの最終メッセージを保存
- `-C "$(pwd)"`: 実行ディレクトリを指定
- `- <`: 標準入力からプロンプトを読み込む

### Step 4: 結果報告

```bash
if [ $EXIT_CODE -eq 0 ]; then
    echo ""
    echo "✅ タスク完了"
    echo ""
    echo "変更ファイル:"
    git status --short
    echo ""
    echo "次のアクション:"
    echo "  1. git diff で変更内容を確認"
    echo "  2. テストを実行"
    echo "  3. 問題なければコミット"

    # 最終メッセージ表示（オプション）
    if [ -f "$RESULT_FILE" ]; then
        echo ""
        echo "Codex からのメッセージ:"
        cat "$RESULT_FILE"
    fi
else
    echo ""
    echo "❌ タスク失敗（終了コード: $EXIT_CODE）"
    echo ""

    # 最終メッセージがあれば表示
    if [ -f "$RESULT_FILE" ]; then
        echo "エラー詳細:"
        cat "$RESULT_FILE"
    fi

    echo ""
    echo "トラブルシューティング:"
    echo "  1. プロンプト内容を確認: cat $PROMPT_FILE"
    echo "  2. Codex を手動実行: codex"
    echo "  3. Claude Code で手動実装"
fi

# クリーンアップ
rm -f "$PROMPT_FILE"
# 結果ファイルは保持（後で確認できるように）
```

---

## Examples

### Example 1: 基本的な実行

**シナリオ:** `user.js` をコールバックから async/await にリファクタリング

```bash
# 1. 環境確認
which codex
codex --version
git rev-parse --git-dir

# 2. プロンプト作成
TIMESTAMP=$(date +%Y%m%d%H%M%S)
PROMPT_FILE="/tmp/codex-prompt-${TIMESTAMP}.md"
RESULT_FILE="/tmp/codex-result-${TIMESTAMP}.txt"

cat > "$PROMPT_FILE" << 'EOF'
# Task: Refactor user.js to async/await

## Objective
Convert callback-based functions in user.js to modern async/await syntax

## Plan
1. Identify all callback functions in user.js
2. Convert each function to async/await
3. Update error handling to try/catch blocks
4. Update corresponding tests
5. Verify all tests pass

## Constraints
- Follow existing code patterns in the repository
- Add tests for all changes
- Update JSDoc comments
- Run `npm test` before completing

## Success Criteria
- All tests pass
- No linting errors
- Code is more readable
EOF

# 3. Codex 実行
codex exec \
  --full-auto \
  --output-last-message "$RESULT_FILE" \
  -C "$(pwd)" \
  - < "$PROMPT_FILE"

# 4. 結果確認
echo $?  # 0なら成功
git status --short
cat "$RESULT_FILE"
```

### Example 2: 複数ファイルのリファクタリング

```bash
cat > "$PROMPT_FILE" << 'EOF'
# Task: Extract shared utilities from controllers

## Objective
Identify common patterns across controllers and extract them into shared utility functions

## Plan
1. Analyze all files in src/controllers/
2. Identify repeated logic (validation, error handling, response formatting)
3. Create src/utils/controller-helpers.js
4. Extract common functions
5. Update all controllers to use the helpers
6. Add unit tests for helpers

## Constraints
- Follow existing naming conventions
- Add comprehensive tests
- Update imports in all affected files
- Ensure backward compatibility

## Success Criteria
- All tests pass
- Controllers are DRYer
- New utilities have 100% test coverage
EOF

codex exec --full-auto --output-last-message "$RESULT_FILE" -C "$(pwd)" - < "$PROMPT_FILE"
```

---

## Best Practices

### 1. Git による安全網

**実行前に必ずコミット:**

```bash
# 現在の作業を保存
git add -A
git commit -m "Before Codex delegation: refactor user module"
```

**または作業ブランチを作成:**

```bash
# 日付付きブランチで安全に実験
git checkout -b codex-refactor-$(date +%Y%m%d)
```

**失敗時の復元:**

```bash
# 変更を破棄して元に戻す
git reset --hard HEAD
```

### 2. プランの粒度

**推奨:**
- タスクは5-10個のステップに分割
- 各ステップは独立して検証可能
- 1回の実行は30分以内が目安

**良い例:**
```markdown
## Plan
1. Add input validation to createUser function
2. Add unit tests for validation
3. Update API documentation
4. Run integration tests
```

**避けるべき例:**
```markdown
## Plan
1. すべてをリファクタリング  ❌ 曖昧すぎる
```

### 3. 成功基準の明確化

**具体的で検証可能な基準を設定:**

```markdown
## Success Criteria
- All tests pass (npm test)
- Code coverage > 80%
- No ESLint errors
- Updated documentation in README.md
```

### 4. 制約条件の明示

**プロジェクト固有のルールを追加:**

```markdown
## Constraints
- Use TypeScript strict mode
- Follow Airbnb style guide
- All new functions must have JSDoc
- Use existing error handling patterns
```

---

## Limitations

### 技術的制限

1. **Codex CLI 依存**
   - Codex CLI のインストールと認証が必須
   - オフライン環境では動作不可
   - OpenAI アカウントが必要

2. **非インタラクティブ制約**
   - ユーザー入力が必要なタスクは実行不可
   - 確認プロンプトは自動承認される（`--full-auto`）
   - 対話的デバッグができない

3. **エラー情報の制限（MVP）**
   - 終了コードのみで成功/失敗を判定
   - 詳細なエラー原因は最終メッセージから手動確認
   - リアルタイムの進捗表示なし

### セキュリティ考慮事項

1. **自動承認のリスク**
   - `--full-auto` はファイル変更を自動承認
   - 重要な操作（本番デプロイなど）には使用しない
   - 予期しない変更が発生する可能性

2. **Git による保護**
   - 実行前に必ずコミット推奨
   - 問題があれば `git reset --hard` で復元可能
   - 作業ブランチでの実行を推奨

### 推奨回避パターン

以下のタスクには使用しないでください:

❌ 本番環境への直接デプロイ
❌ データベースマイグレーションの自動実行
❌ 外部サービスへの課金操作
❌ セキュリティ関連の設定変更
❌ ユーザーデータの削除・変更

---

## Troubleshooting

### Codex CLI がインストールされていない

```
❌ Codex CLI がインストールされていません

解決方法:
  brew install codex-cli
  # または
  npm install -g @openai/codex
```

### 認証エラー

```
❌ Codex CLI の認証が必要です

解決方法:
  codex login
  # ブラウザで OpenAI にログイン
```

### タスク実行失敗

```
❌ タスク失敗（終了コード: 1）

デバッグ手順:
  1. プロンプト内容を確認: cat /tmp/codex-prompt-*.md
  2. 手動で Codex を起動: codex
  3. Claude Code で手動実装を試す
```

### Git リポジトリでない警告

```
⚠️ Git リポジトリではありません

推奨対応:
  git init
  git add -A
  git commit -m "Initial commit"
```

---

## Future Enhancements

このスキルは MVP 実装です。将来的に以下の機能を追加予定:

### Phase 2: AGENTS.md サポート
- プロジェクト固有制約の自動検出
- AGENTS.md テンプレート生成
- カスタム指示の永続化

### Phase 3: 高度なエラーハンドリング
- JSON イベントストリーム解析
- セッション ID 抽出・再開機能
- 自動リトライロジック

### Phase 4: ワークフロー拡張
- バックグラウンド実行サポート
- リアルタイム進捗監視
- 複数タスクの並列実行

---

## References

- [Codex CLI](https://developers.openai.com/codex/cli)
- [Codex CLI Reference](https://developers.openai.com/codex/cli/reference/)
- [Custom instructions with AGENTS.md](https://developers.openai.com/codex/guides/agents-md/)
- [Codex CLI Quick Start](https://jpcaparas.medium.com/codex-cli-quick-start-agents-md-better-prompts-safer-runs-36d7060fcf68)
- [Create custom subagents - Claude Code Docs](https://code.claude.com/docs/en/sub-agents)
- [Awesome Claude Code Subagents](https://github.com/VoltAgent/awesome-claude-code-subagents)
- [GitHub - openai/codex](https://github.com/openai/codex)
