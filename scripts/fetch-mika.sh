#!/usr/bin/env bash
# 把固定版本的 Mika 拉到 ./mika,并打上"可嵌入 + 麦克风互斥"补丁。
# 用法: bash scripts/fetch-mika.sh
# 需要: git。CI 与本地一致(Windows 用 Git Bash 跑)。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MIKA_DIR="$ROOT/mika"
MIKA_REPO="${MIKA_REPO:-https://github.com/wangzan101/Mika.git}"
MIKA_COMMIT="${MIKA_COMMIT:-6661b9e9}"
PATCH="$ROOT/patches/mika-embed.patch"

if [ -d "$MIKA_DIR/.git" ]; then
  git -C "$MIKA_DIR" fetch --filter=blob:none origin "$MIKA_COMMIT"
else
  rm -rf "$MIKA_DIR"
  git clone --filter=blob:none "$MIKA_REPO" "$MIKA_DIR"
  git -C "$MIKA_DIR" fetch --filter=blob:none origin "$MIKA_COMMIT"
fi

git -C "$MIKA_DIR" checkout -q --detach "$MIKA_COMMIT"
git -C "$MIKA_DIR" reset --hard -q "$MIKA_COMMIT"
git -C "$MIKA_DIR" clean -fdxq

git -C "$MIKA_DIR" apply --whitespace=nowarn "$PATCH"
echo "mika ready: $(git -C "$MIKA_DIR" rev-parse --short HEAD) + patches/mika-embed.patch"
