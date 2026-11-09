#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON_BIN="$ROOT_DIR/.venv/bin/python"

# Preserve caller-provided overrides when sourcing project defaults.
OVR_U55C_SWEEP_MODE="${U55C_SWEEP_MODE-}"
OVR_U55C_CONTROL_PATH="${U55C_CONTROL_PATH-}"
OVR_U55C_SCHEDULER_MODE="${U55C_SCHEDULER_MODE-}"
OVR_U55C_SWEEP_SIZES="${U55C_SWEEP_SIZES-}"
OVR_U55C_SWEEP_ITERATIONS="${U55C_SWEEP_ITERATIONS-}"
OVR_U55C_KERNEL_NAME="${U55C_KERNEL_NAME-}"
OVR_U55C_DEVICE_INDEX="${U55C_DEVICE_INDEX-}"
OVR_U55C_TILE_M="${U55C_TILE_M-}"
OVR_U55C_TILE_N="${U55C_TILE_N-}"
OVR_U55C_TILE_K="${U55C_TILE_K-}"
OVR_U55C_XCLBIN="${U55C_XCLBIN-}"

set -a
source "$ROOT_DIR/config/project.env"
set +a

[[ -n "$OVR_U55C_SWEEP_MODE" ]] && U55C_SWEEP_MODE="$OVR_U55C_SWEEP_MODE"
[[ -n "$OVR_U55C_CONTROL_PATH" ]] && U55C_CONTROL_PATH="$OVR_U55C_CONTROL_PATH"
[[ -n "$OVR_U55C_SCHEDULER_MODE" ]] && U55C_SCHEDULER_MODE="$OVR_U55C_SCHEDULER_MODE"
[[ -n "$OVR_U55C_SWEEP_SIZES" ]] && U55C_SWEEP_SIZES="$OVR_U55C_SWEEP_SIZES"
[[ -n "$OVR_U55C_SWEEP_ITERATIONS" ]] && U55C_SWEEP_ITERATIONS="$OVR_U55C_SWEEP_ITERATIONS"
[[ -n "$OVR_U55C_KERNEL_NAME" ]] && U55C_KERNEL_NAME="$OVR_U55C_KERNEL_NAME"
[[ -n "$OVR_U55C_DEVICE_INDEX" ]] && U55C_DEVICE_INDEX="$OVR_U55C_DEVICE_INDEX"
[[ -n "$OVR_U55C_TILE_M" ]] && U55C_TILE_M="$OVR_U55C_TILE_M"
[[ -n "$OVR_U55C_TILE_N" ]] && U55C_TILE_N="$OVR_U55C_TILE_N"
[[ -n "$OVR_U55C_TILE_K" ]] && U55C_TILE_K="$OVR_U55C_TILE_K"
[[ -n "$OVR_U55C_XCLBIN" ]] && U55C_XCLBIN="$OVR_U55C_XCLBIN"

if [[ ! -x "$PYTHON_BIN" ]]; then
  PYTHON_BIN="$(command -v python3)"
fi

CSV_PATH="$ROOT_DIR/results/benchmark_latest.csv"

"$PYTHON_BIN" "$ROOT_DIR/host/python/run_benchmark.py" \
  --mode "${U55C_SWEEP_MODE:-dry-run}" \
  --control "${U55C_CONTROL_PATH:-legacy}" \
  --scheduler "${U55C_SCHEDULER_MODE:-kernel-tiled}" \
  --sizes ${U55C_SWEEP_SIZES:-"65536 262144 1048576 4194304"} \
  --iterations "${U55C_SWEEP_ITERATIONS:-10}" \
  --kernel "${U55C_KERNEL_NAME:-vector_add}" \
  --device "${U55C_DEVICE_INDEX:-0}" \
  --tile-m "${U55C_TILE_M:-16}" \
  --tile-n "${U55C_TILE_N:-16}" \
  --tile-k "${U55C_TILE_K:-16}" \
  --xclbin "${U55C_XCLBIN:-}" \
  --csv "$CSV_PATH"

if "$PYTHON_BIN" -c "import matplotlib.pyplot" >/dev/null 2>&1; then
  "$PYTHON_BIN" "$ROOT_DIR/host/python/plot_results.py" \
    --csv "$CSV_PATH" \
    --out "$ROOT_DIR/results/benchmark_latest.png"
else
  echo "WARNING: matplotlib is not installed; skipping plot generation." >&2
  echo "Install with: $PYTHON_BIN -m pip install -r $ROOT_DIR/host/python/requirements.txt" >&2
fi
