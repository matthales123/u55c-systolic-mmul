#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RTL_DIR="$ROOT_DIR/hardware/rtl"

set -a
source "$ROOT_DIR/config/project.env"
set +a

if [[ -z "${VIVADO_SETTINGS:-}" || ! -f "${VIVADO_SETTINGS}" ]]; then
  echo "ERROR: set VIVADO_SETTINGS in config/project.env (current: ${VIVADO_SETTINGS:-unset})" >&2
  exit 1
fi

export PYTHONPATH="${PYTHONPATH:-}"
export MATLABPATH="${MATLABPATH:-}"
source "$VIVADO_SETTINGS"

cd "$RTL_DIR"
rm -rf xsim.dir

xvlog -sv \
  -i src/cornell \
  -i src/cornell/systolic \
  -i src/cornell/proc \
  -i src/cornell/vc \
  src/cornell/vc/trace.v \
  src/cornell/vc/muxes.v \
  src/cornell/vc/arithmetic.v \
  src/cornell/vc/regs.v \
  src/cornell/vc/regfiles.v \
  src/cornell/vc/queues.v \
  src/cornell/systolic/IntMulBase.v \
  src/cornell/systolic/MacNew.v \
  src/cornell/systolic/SysBase.v \
  src/cornell/proc/control_fsm.v \
  src/cornell/proc/load_unit.v \
  src/cornell/proc/store_unit.v \
  src/cornell/proc/mmulXcel.v

xelab work.systolic_SysBase -s cornell_sysbase_elab
echo "PASS: Cornell RTL compile + SysBase elaboration"
