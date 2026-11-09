#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/webapp_mmul"
VENV_DIR="$APP_DIR/.venv"
WEB_PORT="${MMUL_WEB_PORT:-9890}"
REQUIRE_FLASHED="${MMUL_WEB_REQUIRE_FLASHED_XCLBIN:-1}"
STARTUP_GATE_STATUS="ok"
STARTUP_GATE_MESSAGE="xclbin startup gate passed"
STARTUP_GATE_RC="0"

if [[ ! -d "$VENV_DIR" ]]; then
  python3 -m venv "$VENV_DIR"
fi

# Best-effort firewall rule setup for the active web port.
"$ROOT_DIR/scripts/ensure_webapp_firewall.sh" "$WEB_PORT" || true

# Gate startup on expected xclbin UUID match (enabled by default), but do not block
# web UI availability. Instead, surface a startup warning in the app.
if [[ "$REQUIRE_FLASHED" == "1" ]]; then
  set +e
  GATE_OUTPUT="$("$ROOT_DIR/scripts/check_fpga_xclbin_match.sh" 2>&1)"
  GATE_RC="$?"
  set -e
  if [[ "$GATE_RC" -ne 0 ]]; then
    STARTUP_GATE_STATUS="warn"
    STARTUP_GATE_RC="$GATE_RC"
    GATE_OUTPUT_SINGLE_LINE="$(printf '%s' "$GATE_OUTPUT" | tr '\n' ' ' | tr -s '[:space:]' ' ' | sed -e 's/^ *//' -e 's/ *$//')"
    if [[ -z "$GATE_OUTPUT_SINGLE_LINE" ]]; then
      GATE_OUTPUT_SINGLE_LINE="flashed xclbin check failed with rc=$GATE_RC"
    fi
    STARTUP_GATE_MESSAGE="Flashed xclbin check failed. FPGA actions may fail until a matching bitstream is programmed. Details: ${GATE_OUTPUT_SINGLE_LINE}"
    echo "[webapp] WARNING: $STARTUP_GATE_MESSAGE"
    echo "[webapp] Continuing to launch UI so the issue can be diagnosed from the web app."
  else
    echo "$GATE_OUTPUT"
  fi
else
  STARTUP_GATE_STATUS="skipped"
  STARTUP_GATE_MESSAGE="xclbin startup gate disabled (MMUL_WEB_REQUIRE_FLASHED_XCLBIN=0)"
fi

# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"
python3 -m pip install --upgrade pip >/dev/null
python3 -m pip install -r "$APP_DIR/requirements-web.txt" >/dev/null

exec env \
  MMUL_WEB_PORT="$WEB_PORT" \
  MMUL_WEB_STARTUP_GATE_STATUS="$STARTUP_GATE_STATUS" \
  MMUL_WEB_STARTUP_GATE_MESSAGE="$STARTUP_GATE_MESSAGE" \
  MMUL_WEB_STARTUP_GATE_RC="$STARTUP_GATE_RC" \
  WEBAPP_STARTUP_GATE_STATUS="$STARTUP_GATE_STATUS" \
  WEBAPP_STARTUP_GATE_MESSAGE="$STARTUP_GATE_MESSAGE" \
  WEBAPP_STARTUP_GATE_RC="$STARTUP_GATE_RC" \
  python3 "$APP_DIR/server.py"
