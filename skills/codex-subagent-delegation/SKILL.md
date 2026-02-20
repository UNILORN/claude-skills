---
name: codex-subagent-delegation
description: >
  Claude Code から Codex CLI に実装を委譲して進めるスキル。ユーザーが
  「codexで実装して」「Codexで実装して」「codexに任せて」と依頼したときに使用する。
  Claude は計画作成・委譲・監視・結果報告のみを担当し、ソースコードは直接変更しない。
license: MIT
---

# Codex Subagent Delegation

## Overview

このスキルは、Claude Code 上の実装依頼を Codex CLI に渡して実装させるための運用手順です。

役割分担は固定です。
- Claude: 要件整理、Codex への委譲、進捗監視、結果報告
- Codex: 実装、テスト、必要なドキュメント更新

## When to Use

- ユーザーが `codexで実装して` / `Codexで実装して` / `codexに任せて` と依頼したとき
- Claude が実装方針を把握しており、Codex に実装作業を委譲できるとき
- 長時間または複数ファイルにまたがる実装を自動で進めたいとき

次のケースでは使わない。
- ユーザーとの対話入力が途中で必要なタスク
- 本番デプロイや破壊的操作など、手動承認を必須にしたいタスク

## Non-Negotiable Rules

- Claude は実装中にソースコードを直接編集しない。
- Claude は `apply_patch` などで実装を代行しない。
- 実装変更は Codex CLI の実行結果としてのみ発生させる。
- Codex 実行後、Claude は変更内容を確認して報告する。

## Prerequisites

以下を実行して前提を確認する。

```bash
command -v codex
codex --version
git rev-parse --git-dir
```

前提を満たさない場合の対応。
- `codex` が見つからない: インストール手順を案内して中断
- 認証エラー: `codex login` を案内して中断
- Git リポジトリ外: 警告を出したうえで継続可否を明示

## Workflow

### Step 1: 要件を委譲プロンプトへ変換

ユーザー依頼を Codex 用に構造化する。

```markdown
# Task: <短いタスク名>

## Objective
<何を実装するか>

## In Scope
- <対象1>
- <対象2>

## Out of Scope
- <今回やらないこと>

## Constraints
- Follow existing patterns in this repository
- Keep changes minimal and focused
- Add or update tests for changed behavior
- Update docs only if behavior or usage changes

## Done Criteria
- Requested behavior is implemented
- Relevant tests pass
- `git status --short` で変更が説明可能
```

### Step 2: Codex を実行

`--full-auto` を既定として Codex に実装を委譲する。

```bash
TIMESTAMP="$(date +%Y%m%d%H%M%S)"
PROMPT_FILE="/tmp/codex-prompt-${TIMESTAMP}.md"
RESULT_FILE="/tmp/codex-result-${TIMESTAMP}.txt"

cat > "$PROMPT_FILE" << 'PROMPT'
# Task: <task>

## Objective
<objective>

## In Scope
- <scope>

## Out of Scope
- <out-of-scope>

## Constraints
- Follow existing patterns in this repository
- Keep changes minimal and focused
- Add or update tests for changed behavior
- Update docs only if behavior or usage changes

## Done Criteria
- Requested behavior is implemented
- Relevant tests pass
- `git status --short` is explainable
PROMPT

codex exec \
  --full-auto \
  --output-last-message "$RESULT_FILE" \
  -C "$(pwd)" \
  - < "$PROMPT_FILE"

EXIT_CODE=$?
```

### Step 3: Claude は監視と完了判定のみ行う

- 実行中はログと終了コードを監視する。
- 成功時は変更概要を確認し、ユーザーへ報告する。
- 失敗時は失敗分類に従って再試行または中断する。

```bash
git status --short
[ -f "$RESULT_FILE" ] && cat "$RESULT_FILE"
```

## Failure Handling

### 1) `codex` 未インストール/未認証

- 症状: `command not found` または認証エラー
- 対応: `codex` のインストールまたは `codex login` を案内して停止

### 2) 実行エラー（終了コード非0）

- 症状: `EXIT_CODE != 0`
- 対応: `RESULT_FILE` の内容を報告し、以下のいずれかを選ぶ
  - プロンプトを具体化して再実行
  - スコープを分割して再委譲
  - Claude で方針再整理（実装はしない）

### 3) 変更が期待と乖離

- 症状: 変更ファイルや内容が要求と合わない
- 対応: 差分の乖離点を明示し、修正指示で Codex を再実行

## Reporting Template

Codex 完了後、Claude は次の形式で報告する。

```markdown
Codex 実装が完了しました。

- Result: Success | Failed (exit code: <code>)
- Changed files: <git status --short の要約>
- Notes: <テスト結果や補足>
- Next action: <必要なら再委譲方針>
```

## Example

### User

`codexで実装して。ユーザー作成APIに入力バリデーションを追加してテストも更新して。`

### Claude behavior

1. 要件を Objective / Scope / Constraints / Done Criteria に変換
2. `codex exec --full-auto` で委譲
3. 実行完了まで監視
4. 変更概要と結果を報告

## Limitations

- Codex CLI のインストールと認証が必須
- `--full-auto` のため、委譲前にスコープ明確化が必須
- 対話前提の実装タスクには不向き
