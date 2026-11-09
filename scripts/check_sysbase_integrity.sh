#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIVE_SYSBASE="$ROOT_DIR/hardware/rtl/src/cornell/systolic/SysBase.v"
BASE_DIR="$ROOT_DIR/hardware/rtl/baseline"
BASE_SYSBASE="$BASE_DIR/SysBase.v.orig"

usage() {
  cat <<USAGE
Usage:
  $0 init [--force]
  $0 check

Commands:
  init   Capture current SysBase.v as immutable baseline reference.
  check  Compare current SysBase.v against baseline reference.
USAGE
}

cmd="${1:-check}"
force="${2:-}"

case "$cmd" in
  init)
    if [[ ! -f "$LIVE_SYSBASE" ]]; then
      echo "ERROR: missing live SysBase file: $LIVE_SYSBASE" >&2
      exit 1
    fi
    mkdir -p "$BASE_DIR"
    if [[ -f "$BASE_SYSBASE" && "$force" != "--force" ]]; then
      echo "Baseline already exists: $BASE_SYSBASE"
      echo "Use '$0 init --force' to overwrite."
      exit 0
    fi
    cp -f "$LIVE_SYSBASE" "$BASE_SYSBASE"
    sha256sum "$BASE_SYSBASE" > "$BASE_SYSBASE.sha256"
    echo "Initialized SysBase baseline: $BASE_SYSBASE"
    ;;
  check)
    if [[ ! -f "$LIVE_SYSBASE" ]]; then
      echo "ERROR: missing live SysBase file: $LIVE_SYSBASE" >&2
      exit 1
    fi
    if [[ ! -f "$BASE_SYSBASE" ]]; then
      echo "WARNING: SysBase baseline not initialized. Run:"
      echo "  $0 init"
      exit 0
    fi
    if ! cmp -s "$BASE_SYSBASE" "$LIVE_SYSBASE"; then
      echo "ERROR: SysBase.v differs from baseline."
      echo "Reference: $BASE_SYSBASE"
      echo "Live file : $LIVE_SYSBASE"
      echo "Diff preview:"
      diff -u "$BASE_SYSBASE" "$LIVE_SYSBASE" | sed -n '1,80p'
      exit 1
    fi
    echo "SysBase integrity check PASS."
    ;;
  -h|--help)
    usage
    ;;
  *)
    echo "ERROR: unknown command '$cmd'" >&2
    usage
    exit 1
    ;;
esac
