#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ENV="$ROOT_DIR/config/project.env"

XRT_SMI="${MMUL_WEB_XRT_SMI:-/opt/xilinx/xrt/bin/xrt-smi}"
XCLBINUTIL="${MMUL_WEB_XCLBINUTIL:-/opt/xilinx/xrt/bin/xclbinutil}"

log() {
  echo "[xclbin-check] $*"
}

expand_path() {
  local p="$1"
  p="${p/#\~/$HOME}"
  p="${p//\$HOME/$HOME}"
  printf '%s' "$p"
}

# Load project defaults if present.
if [[ -f "$PROJECT_ENV" ]]; then
  # shellcheck disable=SC1090
  source "$PROJECT_ENV"
fi

DEVICE="${MMUL_WEB_DEVICE:-${U55C_DEVICE_INDEX:-0}}"
EXPECTED_XCLBIN_RAW="${MMUL_WEB_REQUIRED_XCLBIN:-${U55C_XCLBIN:-}}"
EXPECTED_XCLBIN="$(expand_path "$EXPECTED_XCLBIN_RAW")"

resolve_device_bdf() {
  local raw="$1"
  if [[ "$raw" == *:*.* ]]; then
    printf '%s' "$raw"
    return
  fi

  if [[ "$raw" =~ ^[0-9]+$ ]]; then
    local idx="$raw"
    mapfile -t bdfs < <("$XRT_SMI" examine 2>/dev/null | sed -nE 's/.*\[([0-9A-Fa-f:.]+)\].*/\1/p')
    if (( idx < ${#bdfs[@]} )); then
      printf '%s' "${bdfs[$idx]}"
      return
    fi
  fi

  printf '%s' "$raw"
}

if [[ -z "$EXPECTED_XCLBIN" ]]; then
  log "No expected xclbin configured (MMUL_WEB_REQUIRED_XCLBIN/U55C_XCLBIN)."
  exit 1
fi

if [[ ! -f "$EXPECTED_XCLBIN" ]]; then
  log "Expected xclbin not found: $EXPECTED_XCLBIN"
  exit 1
fi

if [[ ! -x "$XRT_SMI" ]]; then
  log "xrt-smi not found/executable at $XRT_SMI"
  exit 1
fi

if [[ ! -x "$XCLBINUTIL" ]]; then
  log "xclbinutil not found/executable at $XCLBINUTIL"
  exit 1
fi

DEVICE_BDF="$(resolve_device_bdf "$DEVICE")"

EXPECTED_UUID="$("$XCLBINUTIL" --info --input "$EXPECTED_XCLBIN" 2>/dev/null \
  | sed -nE 's/.*UUID \(xclbin\):[[:space:]]*([A-Fa-f0-9-]+).*/\1/p' \
  | head -n 1 \
  | tr '[:upper:]' '[:lower:]')"

if [[ -z "$EXPECTED_UUID" ]]; then
  log "Could not parse expected xclbin UUID from $EXPECTED_XCLBIN"
  exit 1
fi

FLASHED_UUID="$("$XRT_SMI" examine --device "$DEVICE_BDF" --report dynamic-regions 2>/dev/null \
  | sed -nE 's/.*Xclbin UUID:[[:space:]]*([A-Fa-f0-9-]+).*/\1/p' \
  | head -n 1 \
  | tr '[:upper:]' '[:lower:]')"

if [[ -z "$FLASHED_UUID" ]]; then
  log "Could not read flashed xclbin UUID from device '$DEVICE' (resolved: '$DEVICE_BDF')"
  exit 1
fi

if [[ "$EXPECTED_UUID" != "$FLASHED_UUID" ]]; then
  log "UUID mismatch on device '$DEVICE' (resolved: '$DEVICE_BDF')"
  log "Expected: $EXPECTED_UUID"
  log "Flashed : $FLASHED_UUID"
  exit 42
fi

log "UUID match OK on device '$DEVICE' (resolved: '$DEVICE_BDF') ($FLASHED_UUID)"
