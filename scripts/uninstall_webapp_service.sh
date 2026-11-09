#!/usr/bin/env bash
set -euo pipefail

UNIT_NAME="u55c-mmul-webapp.service"
UNIT_PATH="$HOME/.config/systemd/user/$UNIT_NAME"

if systemctl --user list-unit-files | rg -q "^${UNIT_NAME}"; then
  systemctl --user disable --now "$UNIT_NAME" || true
fi

rm -f "$UNIT_PATH"
systemctl --user daemon-reload

echo "[service] removed: $UNIT_PATH"
