#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
UPSTREAM=${1:?usage: apply.sh /path/to/writable/upstream-micyou-checkout}
BASELINE=0c69fdd4b0c26553bd4a74aed38a808f0fce621a
TARGET="$UPSTREAM/tauri-app/crates/micyou-cli/src/jsonl.rs"
PATCH="$SCRIPT_DIR/../0001-cli-jsonl-control-channel.patch"

ACTUAL=$(git -C "$UPSTREAM" rev-parse HEAD)
if [ "$ACTUAL" != "$BASELINE" ]; then
  echo "Expected upstream commit $BASELINE; found $ACTUAL" >&2
  exit 1
fi
if [ -n "$(git -C "$UPSTREAM" status --porcelain)" ]; then
  echo "Refusing to patch a dirty upstream checkout" >&2
  exit 1
fi
if [ -e "$TARGET" ]; then
  echo "Refusing to overwrite existing file: $TARGET" >&2
  exit 1
fi

git -C "$UPSTREAM" apply --check "$PATCH"
cp "$SCRIPT_DIR/src/jsonl.rs" "$TARGET"
git -C "$UPSTREAM" apply "$PATCH"
echo "Applied JSONL control bridge to $UPSTREAM"
