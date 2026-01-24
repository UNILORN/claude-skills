---
name: github-pr-description
description: Generate or overwrite a GitHub Pull Request description by analyzing the current branch PR changes and template, using the GitHub CLI (gh). Use when the user asks to draft or update a PR description based on diffs, branch-linked issue numbers (e.g., */123), or when gh pr/gh pr diff should be used.
---

# GitHub PR Description

## Goal

Create or update the PR description for the current branch using the repository PR template and the latest diff, filling in a concise summary and change list.

## Workflow

### 1) Gather context with gh

- Run `gh pr view --json title,body,number,headRefName` to get the current PR body and branch name.
- Run `gh pr diff` to review changes and extract key updates for the summary and change list.

### 2) Detect related issue from branch name

- If the branch name contains a numeric segment like `*/123`, treat it as issue `#123`.
- Use `gh issue view 123` and include any design intent or constraints that clarify the PR summary or scope.

### 3) Decide whether to overwrite

- If the existing PR body is empty or has minimal content (e.g., only placeholders), overwrite it with the template-driven description.
- If the body already has substantial content, update only missing sections while preserving user-written details.

### 4) Populate the template

Use the following template and fill it from the diff and issue context:

```markdown
## 概要

<!-- この PR の目的と概要を簡潔に説明してください。 -->

## 変更点

<!--  具体的な変更点や修正箇所を箇条書きでリストアップしてください。レビュワーは確認が完了した項目にチェックを入れてください。 -->

- [ ] 変更点 1
- [ ] 変更点 2
- [ ] 変更点 3

## 影響範囲

<!-- この PR が影響を及ぼす範囲や他の機能への影響を説明してください。 -->

## 動作確認

<!-- スクリーンショット or 動画を添付してください。 -->

## レビュアーへの注意事項

<!-- 特に確認してほしい点や、実装上の判断についてレビュワーに共有したい内容を記載してください。 -->

## 作成者チェックリスト

- [ ] テストを追加・更新しました
- [ ] 既存の機能に影響がないことを確認しました
- [ ] 必要なドキュメントを更新しました
- [ ] コードの品質（可読性、保守性）を確認しました

## 関連 Issue

<!-- この PR が関連する Issue やタスクをリンクしてください。以下のように記述します。　-->

- close: #
```

### 5) Fill specific rules

- In **関連 Issue**, set `- close: #<issue-number>` when an issue number is detected from the branch name.
- Do not add screenshots or videos; leave **動作確認** as a placeholder.
- Keep **変更点** as checklist items derived from the diff.

### 6) Update the PR body

- Use `gh pr edit --body-file <file>` or `gh pr edit --body <text>` to apply the updated description.
- Prefer writing to a temp file to avoid shell escaping issues.

## Notes

- Always operate on the PR for the current branch.
- Keep the summary concise and accurate to the diff.
