#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Deploy MQL5 folder to a MetaTrader 5 Data Folder.

Usage:
  $0 --data-dir "/absolute/path/to/MetaTrader Data Folder" [--mode copy|symlink]

Notes:
  - In MetaTrader 5: File -> Open Data Folder (this is the --data-dir)
  - This script copies or symlinks the repo's MQL5 into that folder.
  - Symlinking requires permissions (admin on Windows when using mklink).

Examples:
  bash tools/deploy.sh --data-dir "/path/to/Terminal/XXXXXXXXXXXX" --mode copy
  bash tools/deploy.sh --data-dir "/path/to/Terminal/XXXXXXXXXXXX" --mode symlink
EOF
}

DATA_DIR=""
MODE="copy"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --data-dir)
      DATA_DIR="$2"; shift 2 ;;
    --mode)
      MODE="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$DATA_DIR" ]]; then
  echo "--data-dir is required" >&2
  usage
  exit 1
fi

if [[ ! -d "$DATA_DIR" ]]; then
  echo "Data dir does not exist: $DATA_DIR" >&2
  exit 1
fi

SRC_MQL5="$(cd "$(dirname "$0")/.." && pwd)/MQL5"
DST_MQL5="$DATA_DIR/MQL5"

echo "Source: $SRC_MQL5"
echo "Target: $DST_MQL5"

mkdir -p "$DST_MQL5"

case "$MODE" in
  copy)
    echo "Copying MQL5 contents..."
    rsync -a --exclude=".git" "$SRC_MQL5/" "$DST_MQL5/"
    ;;
  symlink)
    echo "Symlinking subfolders (Scripts, Experts, Include, Libraries, Files)..."
    for sub in Scripts Experts Include Libraries Files; do
      src="$SRC_MQL5/$sub"
      dst="$DST_MQL5/$sub"
      mkdir -p "$DST_MQL5"
      if [[ -e "$dst" || -L "$dst" ]]; then
        echo "Skipping existing: $dst"
      else
        ln -s "$src" "$dst"
        echo "Linked $dst -> $src"
      fi
    done
    ;;
  *)
    echo "Unknown mode: $MODE (use copy|symlink)" >&2
    exit 1
    ;;
esac

echo "Done. Open MetaEditor to compile your scripts."
