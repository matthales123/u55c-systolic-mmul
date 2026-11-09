#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UNIT_SRC="$ROOT_DIR/services/u55c-mmul-webapp.service"
UNIT_DIR="$HOME/.config/systemd/user"
UNIT_DST="$UNIT_DIR/u55c-mmul-webapp.service"
ENABLE_NOW="${1:-}"

mkdir -p "$UNIT_DIR"
cp -f "$UNIT_SRC" "$UNIT_DST"

systemctl --user daemon-reload

if [[ "$ENABLE_NOW" == "--enable-now" ]]; then
  systemctl --user enable --now u55c-mmul-webapp.service
  echo "[service] enabled + started: u55c-mmul-webapp.service"
else
  echo "[service] installed: $UNIT_DST"
  echo "[service] next:"
  echo "  systemctl --user enable --now u55c-mmul-webapp.service"
fi

echo "[service] status command:"
echo "  systemctl --user status u55c-mmul-webapp.service --no-pager"
