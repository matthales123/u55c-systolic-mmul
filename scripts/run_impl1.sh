#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TCL_SCRIPT="$ROOT_DIR/hardware/hls/scripts/run_impl1.tcl"
DEFAULT_XPR_NEW="$ROOT_DIR/_x/link/vivado/vpl/prj/prj.xpr"
DEFAULT_XPR_OLD="$ROOT_DIR/hardware/hls/_x/link/vivado/vpl/prj/prj.xpr"

RUN_NAME="impl_1"
JOBS=44
TO_STEP="write_bitstream"
RESET=0
XPR_PATH="$DEFAULT_XPR_NEW"
if [[ ! -f "$XPR_PATH" && -f "$DEFAULT_XPR_OLD" ]]; then
  XPR_PATH="$DEFAULT_XPR_OLD"
fi

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --xpr <path>        Vivado project (.xpr) path
  --run <name>        Implementation run name (default: impl_1)
  --jobs <n>          Parallel jobs for launch_runs (default: 44)
  --to-step <step>    Stop step (default: write_bitstream)
  --reset             Reset run before launch (forces full re-run)
  -h, --help          Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --xpr)
      XPR_PATH="$2"
      shift 2
      ;;
    --run)
      RUN_NAME="$2"
      shift 2
      ;;
    --jobs)
      JOBS="$2"
      shift 2
      ;;
    --to-step)
      TO_STEP="$2"
      shift 2
      ;;
    --reset)
      RESET=1
      shift 1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument '$1'"
      usage
      exit 1
      ;;
  esac
done

if [[ ! -f "$XPR_PATH" ]]; then
  echo "ERROR: Vivado project not found: $XPR_PATH"
  echo "Build hardware first so VPL generates prj.xpr."
  exit 1
fi

if ! command -v vivado >/dev/null 2>&1; then
  if [[ -f /tools/Xilinx/2025.1/Vivado/settings64.sh ]]; then
    # shellcheck disable=SC1091
    source /tools/Xilinx/2025.1/Vivado/settings64.sh
  fi
fi

if ! command -v vivado >/dev/null 2>&1; then
  echo "ERROR: vivado is not in PATH."
  echo "Source your Vivado/Vitis settings script and retry."
  exit 1
fi

echo "[impl] xpr=$XPR_PATH"
echo "[impl] run=$RUN_NAME"
echo "[impl] jobs=$JOBS"
echo "[impl] to_step=$TO_STEP"
echo "[impl] reset=$RESET"

vivado -mode batch -source "$TCL_SCRIPT" -tclargs "$XPR_PATH" "$RUN_NAME" "$JOBS" "$TO_STEP" "$RESET"
