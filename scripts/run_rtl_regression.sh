#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP="$(date +%Y%m%d_%H%M%S)"
OUT_DIR="$ROOT_DIR/results/rtl_regression/$STAMP"
mkdir -p "$OUT_DIR"

run_one() {
  local name="$1"
  local top="$2"
  local tb="$3"
  local log_file="$OUT_DIR/${name}.log"

  echo "[rtl-regression] running $name (top=$top tb=$tb)"
  (
    cd "$ROOT_DIR"
    U55C_RTL_TOP="$top" U55C_RTL_TB_TOP="$tb" ./hardware/rtl/run_sim.sh
  ) >"$log_file" 2>&1

  if ! rg -q "PASS: ${tb}" "$log_file"; then
    echo "[rtl-regression] FAIL: $name"
    echo "  log: $log_file"
    return 1
  fi

  echo "[rtl-regression] PASS: $name"
}

run_one "sysbase_shell" "mmul_sysbase_axis_shell" "mmul_sysbase_axis_shell_tb"
run_one "sysbase_xcel" "mmul_sysbase_xcel" "mmul_sysbase_xcel_tb"

(
  cd "$ROOT_DIR"
  ./scripts/check_sysbase_integrity.sh check
) >>"$OUT_DIR/summary.log" 2>&1

echo "[rtl-regression] complete"
echo "[rtl-regression] logs: $OUT_DIR"
