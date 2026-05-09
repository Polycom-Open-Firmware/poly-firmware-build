#!/usr/bin/env bash
# images/dtbo.sh — wrap raw imx8mm-tc8.dtb as a "dtbo" partition image and AVB-sign.
#
# Note: this is not a real Android dt-overlay image, just the same dtb as inside
# Image-with-dtb stuffed into the dtbo slot for AVB descriptor coverage. Matches the
# stock packaging.
#
# USAGE
#   images/dtbo.sh --dtb=PATH [--avb-key=KEY] [--out=FILE] [--partition-size=BYTES]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

DTB=""
AVB_KEY="${TC8_AVB_KEY:-}"
OUT=""
PART_SIZE="4194304"   # 4 MiB
ALG="SHA256_RSA4096"

usage() {
  cat <<EOF
images/dtbo.sh — wrap dtb as dtbo.img and AVB-sign

USAGE
  images/dtbo.sh --dtb=PATH [options]

REQUIRED
  --dtb=PATH           Path to imx8mm-tc8.dtb (out/kernel/imx8mm-tc8.dtb)

OPTIONS
  --avb-key=KEY        AVB key (default: \$TC8_AVB_KEY)
  --out=FILE           Output (default: ./out/dtbo.img)
  --partition-size=N   AVB partition_size (default $PART_SIZE)
  -h, --help           Show this help
EOF
}

for arg in "$@"; do
  case "$arg" in
    --dtb=*) DTB="${arg#--dtb=}";;
    --avb-key=*) AVB_KEY="${arg#--avb-key=}";;
    --out=*) OUT="${arg#--out=}";;
    --partition-size=*) PART_SIZE="${arg#--partition-size=}";;
    -h|--help) usage; exit 0;;
    *) echo "unknown arg: $arg" >&2; exit 1;;
  esac
done

[[ -n "$DTB"     ]] || { echo "ERROR: --dtb= required" >&2; exit 1; }
[[ -f "$DTB"     ]] || { echo "ERROR: dtb not found: $DTB" >&2; exit 1; }
[[ -n "$AVB_KEY" ]] || { echo "ERROR: --avb-key= or TC8_AVB_KEY required" >&2; exit 1; }
[[ -f "$AVB_KEY" ]] || { echo "ERROR: avb key not found: $AVB_KEY" >&2; exit 1; }
[[ -n "$OUT" ]] || OUT="$REPO_ROOT/out/dtbo.img"

AVBTOOL="$REPO_ROOT/vendored/avb/avbtool.py"
[[ -f "$AVBTOOL" ]] || { echo "ERROR: $AVBTOOL missing" >&2; exit 1; }

mkdir -p "$(dirname "$OUT")"
cp "$DTB" "$OUT"

echo "[+] avbtool add_hash_footer dtbo (partition_size=$PART_SIZE)"
python3 "$AVBTOOL" add_hash_footer \
  --partition_name dtbo \
  --partition_size "$PART_SIZE" \
  --image "$OUT" \
  --algorithm "$ALG" \
  --key "$AVB_KEY"

ls -la "$OUT"
echo "[OK] $OUT"
