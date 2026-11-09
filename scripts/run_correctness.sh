#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT_DIR/build/host/u55c_bench"
CSV="$ROOT_DIR/results/correctness.csv"
PYTHON_BIN="$ROOT_DIR/.venv/bin/python"

# Preserve caller-provided overrides when sourcing project defaults.
OVR_U55C_XCLBIN="${U55C_XCLBIN-}"
OVR_U55C_CONTROL_PATH="${U55C_CONTROL_PATH-}"
OVR_U55C_SCHEDULER_MODE="${U55C_SCHEDULER_MODE-}"
OVR_U55C_KERNEL_NAME="${U55C_KERNEL_NAME-}"
OVR_U55C_DEVICE_INDEX="${U55C_DEVICE_INDEX-}"
OVR_U55C_DEFAULT_ELEMENTS="${U55C_DEFAULT_ELEMENTS-}"
OVR_U55C_TILE_M="${U55C_TILE_M-}"
OVR_U55C_TILE_N="${U55C_TILE_N-}"
OVR_U55C_TILE_K="${U55C_TILE_K-}"

set -a
source "$ROOT_DIR/config/project.env"
set +a

[[ -n "$OVR_U55C_XCLBIN" ]] && U55C_XCLBIN="$OVR_U55C_XCLBIN"
[[ -n "$OVR_U55C_CONTROL_PATH" ]] && U55C_CONTROL_PATH="$OVR_U55C_CONTROL_PATH"
[[ -n "$OVR_U55C_SCHEDULER_MODE" ]] && U55C_SCHEDULER_MODE="$OVR_U55C_SCHEDULER_MODE"
[[ -n "$OVR_U55C_KERNEL_NAME" ]] && U55C_KERNEL_NAME="$OVR_U55C_KERNEL_NAME"
[[ -n "$OVR_U55C_DEVICE_INDEX" ]] && U55C_DEVICE_INDEX="$OVR_U55C_DEVICE_INDEX"
[[ -n "$OVR_U55C_DEFAULT_ELEMENTS" ]] && U55C_DEFAULT_ELEMENTS="$OVR_U55C_DEFAULT_ELEMENTS"
[[ -n "$OVR_U55C_TILE_M" ]] && U55C_TILE_M="$OVR_U55C_TILE_M"
[[ -n "$OVR_U55C_TILE_N" ]] && U55C_TILE_N="$OVR_U55C_TILE_N"
[[ -n "$OVR_U55C_TILE_K" ]] && U55C_TILE_K="$OVR_U55C_TILE_K"

if [[ ! -x "$PYTHON_BIN" ]]; then
  PYTHON_BIN="$(command -v python3)"
fi

RESOLVED_XCLBIN="${U55C_XCLBIN:-}"
if [[ -n "$RESOLVED_XCLBIN" && "$RESOLVED_XCLBIN" != /* ]]; then
  RESOLVED_XCLBIN="$ROOT_DIR/$RESOLVED_XCLBIN"
fi

"$ROOT_DIR/scripts/build_host.sh"

"$BIN" \
  --mode dry-run \
  --control "${U55C_CONTROL_PATH:-legacy}" \
  --scheduler "${U55C_SCHEDULER_MODE:-kernel-tiled}" \
  --kernel "${U55C_KERNEL_NAME:-mmul}" \
  --device "${U55C_DEVICE_INDEX:-0}" \
  --elements "${U55C_DEFAULT_ELEMENTS:-1024}" \
  --iterations 3 \
  --tile-m "${U55C_TILE_M:-16}" \
  --tile-n "${U55C_TILE_N:-16}" \
  --tile-k "${U55C_TILE_K:-16}" \
  --csv "$CSV"

"$PYTHON_BIN" "$ROOT_DIR/tests/test_csv_schema.py" "$CSV"

echo "Dry-run correctness: PASS"

if [[ -n "$RESOLVED_XCLBIN" ]]; then
  if [[ ! -f "$RESOLVED_XCLBIN" ]]; then
    echo "WARNING: U55C_XCLBIN is set but file is missing: $RESOLVED_XCLBIN"
    exit 0
  fi

  "$BIN" \
    --mode hw \
    --xclbin "$RESOLVED_XCLBIN" \
    --control "${U55C_CONTROL_PATH:-legacy}" \
    --scheduler "${U55C_SCHEDULER_MODE:-kernel-tiled}" \
    --kernel "${U55C_KERNEL_NAME:-mmul}" \
    --device "${U55C_DEVICE_INDEX:-0}" \
    --elements "${U55C_DEFAULT_ELEMENTS:-1024}" \
    --iterations 1 \
    --tile-m "${U55C_TILE_M:-16}" \
    --tile-n "${U55C_TILE_N:-16}" \
    --tile-k "${U55C_TILE_K:-16}" \
    --csv "$CSV"

  echo "Hardware correctness: PASS"
else
  echo "Hardware correctness skipped (set U55C_XCLBIN in config/project.env)."
fi
