#!/bin/zsh
set -euo pipefail
ROOT=${0:A:h:h}
"$ROOT/scripts/build-app.sh" >/dev/null
pkill -x Lecture 2>/dev/null || true
rm -rf /Applications/Lecture.app
cp -R "$ROOT/dist/Lecture.app" /Applications/Lecture.app
if [[ -n "${LECTURE_DEEPSEEK_API_KEY:-}" ]]; then
  KEY_DIR="$HOME/Library/Application Support/Lecture"
  mkdir -p "$KEY_DIR"
  umask 077
  printf %s "$LECTURE_DEEPSEEK_API_KEY" > "$KEY_DIR/.pending-deepseek-key"
fi
open /Applications/Lecture.app
echo /Applications/Lecture.app
