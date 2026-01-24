#!/usr/bin/env sh
set -eu

REPO_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SOURCE_DIR="$REPO_ROOT/skills"
TARGET_DIR="${CODEX_HOME:-$HOME/.codex}/skills"

DELETE_FLAG=""
if [ "${1:-}" = "--delete" ]; then
  DELETE_FLAG="--delete"
fi

mkdir -p "$TARGET_DIR"

if command -v rsync >/dev/null 2>&1; then
  rsync -a $DELETE_FLAG --exclude ".DS_Store" "$SOURCE_DIR"/ "$TARGET_DIR"/
else
  if [ -n "$DELETE_FLAG" ]; then
    echo "rsync not found; --delete is unavailable with cp." >&2
    exit 1
  fi
  cp -R "$SOURCE_DIR"/. "$TARGET_DIR"/
fi

echo "Synced skills to $TARGET_DIR"
