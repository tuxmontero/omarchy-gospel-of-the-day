#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
HELPER="$SCRIPT_DIR/evangelizo.py"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/gospel-of-the-day"
ALLOWED_LANGS="SP AM FR IT DE PT AR PL NL GR MG TRA TRS TRF TRD ARM BYA COA MAA SYA"

lang=""
date_arg=""
refresh=0

while (($# > 0)); do
  case "$1" in
  --lang)
    lang="${2:-}"
    shift 2
    ;;
  --date)
    date_arg="${2:-}"
    shift 2
    ;;
  --refresh)
    refresh=1
    shift
    ;;
  *)
    echo "invalid argument: $1" >&2
    exit 2
    ;;
  esac
done

lang=$(printf '%s' "$lang" | tr '[:lower:]' '[:upper:]')
case " $ALLOWED_LANGS " in
*" $lang "*) ;;
*)
  echo "invalid language: $lang" >&2
  exit 2
  ;;
esac

if [[ -z $date_arg || ! $date_arg =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "invalid date: $date_arg" >&2
  exit 2
fi

if ! command -v systemd-run >/dev/null; then
  echo "systemd-run is required" >&2
  exit 3
fi

mkdir -p "$CACHE_DIR"

args=(--lang "$lang" --date "$date_arg")
if ((refresh)); then
  args+=(--refresh)
fi

exec systemd-run --user --quiet --pipe --wait --collect \
  --property=NoNewPrivileges=yes \
  --property=ProtectHome=read-only \
  --property=ProtectSystem=strict \
  --property=PrivateTmp=yes \
  --property=ReadWritePaths="$CACHE_DIR" \
  --property=MemoryMax=64M \
  --property=TasksMax=32 \
  --property=RuntimeMaxSec=45 \
  -- \
  python3 "$HELPER" "${args[@]}"
