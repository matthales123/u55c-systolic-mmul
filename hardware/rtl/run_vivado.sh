#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RTL_DIR="$ROOT_DIR/hardware/rtl"
SYSBASE_CHECK="$ROOT_DIR/scripts/check_sysbase_integrity.sh"

# Preserve caller-provided overrides when sourcing project defaults.
OVR_U55C_RTL_PROJECT_NAME="${U55C_RTL_PROJECT_NAME-}"
OVR_U55C_RTL_TOP="${U55C_RTL_TOP-}"
OVR_U55C_RTL_TB_TOP="${U55C_RTL_TB_TOP-}"
OVR_U55C_PART="${U55C_PART-}"
OVR_U55C_BOARD_REPO_PATHS="${U55C_BOARD_REPO_PATHS-}"
OVR_VIVADO_SETTINGS="${VIVADO_SETTINGS-}"

set -a
source "$ROOT_DIR/config/project.env"
set +a

[[ -n "$OVR_U55C_RTL_PROJECT_NAME" ]] && U55C_RTL_PROJECT_NAME="$OVR_U55C_RTL_PROJECT_NAME"
[[ -n "$OVR_U55C_RTL_TOP" ]] && U55C_RTL_TOP="$OVR_U55C_RTL_TOP"
[[ -n "$OVR_U55C_RTL_TB_TOP" ]] && U55C_RTL_TB_TOP="$OVR_U55C_RTL_TB_TOP"
[[ -n "$OVR_U55C_PART" ]] && U55C_PART="$OVR_U55C_PART"
[[ -n "$OVR_U55C_BOARD_REPO_PATHS" ]] && U55C_BOARD_REPO_PATHS="$OVR_U55C_BOARD_REPO_PATHS"
[[ -n "$OVR_VIVADO_SETTINGS" ]] && VIVADO_SETTINGS="$OVR_VIVADO_SETTINGS"

if [[ -z "${VIVADO_SETTINGS:-}" || ! -f "${VIVADO_SETTINGS}" ]]; then
  echo "ERROR: set VIVADO_SETTINGS in config/project.env (current: ${VIVADO_SETTINGS:-unset})" >&2
  exit 1
fi

export PYTHONPATH="${PYTHONPATH:-}"
export MATLABPATH="${MATLABPATH:-}"
source "$VIVADO_SETTINGS"

if [[ -x "$SYSBASE_CHECK" ]]; then
  "$SYSBASE_CHECK" check
fi

build_board_repo_paths() {
  local raw="${U55C_BOARD_REPO_PATHS:-}"
  if [[ -z "$raw" ]]; then
    raw="/opt/xilinx/board_files/u55c:$HOME/xilinx_board_files/u55c"
  fi

  local -a candidates=()
  local -a existing=()
  IFS=':' read -r -a candidates <<< "$raw"
  for repo in "${candidates[@]}"; do
    [[ -n "$repo" ]] || continue
    if [[ -d "$repo" ]]; then
      existing+=("$repo")
    fi
  done

  if [[ ${#existing[@]} -gt 0 ]]; then
    local joined=""
    for repo in "${existing[@]}"; do
      if [[ -z "$joined" ]]; then
        joined="$repo"
      else
        joined="${joined}:$repo"
      fi
    done
    printf '%s\n' "$joined"
  fi
}

U55C_EFFECTIVE_BOARD_REPO_PATHS="$(build_board_repo_paths)"
export U55C_EFFECTIVE_BOARD_REPO_PATHS

cd "$RTL_DIR"
vivado -mode batch -source scripts/project.tcl
