#!/usr/bin/env bash
# images/vbmeta.sh — build vbmeta.img covering boot + system + dtbo descriptors.
#
# USAGE
#   images/vbmeta.sh --boot=FILE --system=FILE --dtbo=FILE [--avb-key=KEY] [--out=FILE]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

BOOT=""; SYSTEM=""; DTBO=""
AVB_KEY="${TC8_AVB_KEY:-}"
OUT=""
PADDING_SIZE="1048576"
ALG="SHA256_RSA4096"

usage() {
  cat <<EOF
images/vbmeta.sh — build vbmeta.img referencing boot/system/dtbo descriptors

USAGE
  images/vbmeta.sh --boot=FILE --system=FILE --dtbo=FILE [options]

OPTIONS
  --avb-key=KEY        AVB key (default: \$TC8_AVB_KEY)
  --out=FILE           Output (default: ./out/vbmeta.img)
  --padding-size=N     vbmeta pad size (default $PADDING_SIZE)
  -h, --help           Show this help
EOF
}

for arg in "$@"; do
  case "$arg" in
    --boot=*)   BOOT="${arg#--boot=}";;
    --system=*) SYSTEM="${arg#--system=}";;
    --dtbo=*)   DTBO="${arg#--dtbo=}";;
    --avb-key=*) AVB_KEY="${arg#--avb-key=}";;
    --out=*)     OUT="${arg#--out=}";;
    --padding-size=*) PADDING_SIZE="${arg#--padding-size=}";;
    -h|--help) usage; exit 0;;
    *) echo "unknown arg: $arg" >&2; exit 1;;
  esac
done

for v in BOOT SYSTEM DTBO; do
  eval "p=\${$v}"
  [[ -n "$p" ]] || { echo "ERROR: --${v,,}= required" >&2; exit 1; }
  [[ -f "$p" ]] || { echo "ERROR: not found: $p" >&2; exit 1; }
done
[[ -n "$AVB_KEY" ]] || { echo "ERROR: --avb-key= or TC8_AVB_KEY required" >&2; exit 1; }
[[ -f "$AVB_KEY" ]] || { echo "ERROR: avb key not found: $AVB_KEY" >&2; exit 1; }
[[ -n "$OUT" ]] || OUT="$REPO_ROOT/out/vbmeta.img"

AVBTOOL="$REPO_ROOT/vendored/avb/avbtool.py"
[[ -f "$AVBTOOL" ]] || { echo "ERROR: $AVBTOOL missing" >&2; exit 1; }

mkdir -p "$(dirname "$OUT")"

echo "[+] avbtool make_vbmeta_image -> $OUT"
python3 "$AVBTOOL" make_vbmeta_image \
  --output "$OUT" \
  --algorithm "$ALG" \
  --key "$AVB_KEY" \
  --include_descriptors_from_image "$BOOT" \
  --include_descriptors_from_image "$SYSTEM" \
  --include_descriptors_from_image "$DTBO" \
  --padding_size "$PADDING_SIZE"

ls -la "$OUT"
echo "[OK] $OUT"
