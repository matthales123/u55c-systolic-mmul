#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

DEFAULT_SRC="$HOME/Documents/Coding Projects/Cornell_Projects/ECE5745_FP/project-group14-main/sim"
SRC_SIM_DIR="${1:-$DEFAULT_SRC}"

if [[ ! -d "$SRC_SIM_DIR" ]]; then
  echo "ERROR: source sim directory not found: $SRC_SIM_DIR" >&2
  exit 1
fi

DEST_DIR="$ROOT_DIR/hardware/rtl/src/cornell"
mkdir -p "$DEST_DIR/systolic" "$DEST_DIR/proc" "$DEST_DIR/vc"

copy_file() {
  local src="$1"
  local dst="$2"
  if [[ ! -f "$src" ]]; then
    echo "ERROR: missing source file: $src" >&2
    exit 1
  fi
  cp -f "$src" "$dst"
  echo "synced: $dst"
}

copy_file "$SRC_SIM_DIR/systolic/IntMulBase.v" "$DEST_DIR/systolic/IntMulBase.v"
copy_file "$SRC_SIM_DIR/systolic/MacNew.v" "$DEST_DIR/systolic/MacNew.v"
copy_file "$SRC_SIM_DIR/systolic/SysBase.v" "$DEST_DIR/systolic/SysBase.v"

copy_file "$SRC_SIM_DIR/proc/control_fsm.v" "$DEST_DIR/proc/control_fsm.v"
copy_file "$SRC_SIM_DIR/proc/load_unit.v" "$DEST_DIR/proc/load_unit.v"
copy_file "$SRC_SIM_DIR/proc/store_unit.v" "$DEST_DIR/proc/store_unit.v"
copy_file "$SRC_SIM_DIR/proc/mmulXcel.v" "$DEST_DIR/proc/mmulXcel.v"

copy_file "$SRC_SIM_DIR/vc/trace.v" "$DEST_DIR/vc/trace.v"
copy_file "$SRC_SIM_DIR/vc/muxes.v" "$DEST_DIR/vc/muxes.v"
copy_file "$SRC_SIM_DIR/vc/arithmetic.v" "$DEST_DIR/vc/arithmetic.v"
copy_file "$SRC_SIM_DIR/vc/regs.v" "$DEST_DIR/vc/regs.v"
copy_file "$SRC_SIM_DIR/vc/regfiles.v" "$DEST_DIR/vc/regfiles.v"
copy_file "$SRC_SIM_DIR/vc/queues.v" "$DEST_DIR/vc/queues.v"

echo "Cornell RTL sync complete."
