#!/usr/bin/env bash
# images/system.sh — build a fixed-size ext4 system.img from a rootfs tarball or
# directory, then add an AVB hashtree footer.
#
# USAGE
#   images/system.sh --rootfs=PATH [--avb-key=KEY] [--out=FILE]
#                    [--image-size=BYTES] [--partition-size=BYTES]
#
# --rootfs may be a .tar / .tar.gz / .tar.xz / .tar.zst, or a directory.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

ROOTFS=""
AVB_KEY="${TC8_AVB_KEY:-}"
OUT=""
IMAGE_SIZE="1500000000"     # ext4 image size before AVB footer
PART_SIZE="1879048192"      # 1792 MiB AVB partition size
ALG="SHA256_RSA4096"
LABEL="tc8-system"

usage() {
  cat <<EOF
images/system.sh — build + AVB-sign system.img

USAGE
  images/system.sh --rootfs=PATH [options]

REQUIRED
  --rootfs=PATH        Tarball (.tar[.gz|.xz|.zst]) or directory containing rootfs

OPTIONS
  --avb-key=KEY        AVB key (default: \$TC8_AVB_KEY)
  --out=FILE           Output (default: ./out/system.img)
  --image-size=N       ext4 image size (default $IMAGE_SIZE)
  --partition-size=N   AVB partition_size (default $PART_SIZE)
  -h, --help           Show this help
EOF
}

for arg in "$@"; do
  case "$arg" in
    --rootfs=*) ROOTFS="${arg#--rootfs=}";;
    --avb-key=*) AVB_KEY="${arg#--avb-key=}";;
    --out=*) OUT="${arg#--out=}";;
    --image-size=*) IMAGE_SIZE="${arg#--image-size=}";;
    --partition-size=*) PART_SIZE="${arg#--partition-size=}";;
    -h|--help) usage; exit 0;;
    *) echo "unknown arg: $arg" >&2; exit 1;;
  esac
done

[[ -n "$ROOTFS"  ]] || { echo "ERROR: --rootfs= required" >&2; exit 1; }
[[ -e "$ROOTFS"  ]] || { echo "ERROR: rootfs not found: $ROOTFS" >&2; exit 1; }
[[ -n "$AVB_KEY" ]] || { echo "ERROR: --avb-key= or TC8_AVB_KEY required" >&2; exit 1; }
[[ -f "$AVB_KEY" ]] || { echo "ERROR: avb key not found: $AVB_KEY" >&2; exit 1; }
[[ -n "$OUT" ]] || OUT="$REPO_ROOT/out/system.img"

AVBTOOL="$REPO_ROOT/vendored/avb/avbtool.py"
[[ -f "$AVBTOOL" ]] || { echo "ERROR: $AVBTOOL missing" >&2; exit 1; }
command -v mkfs.ext4 >/dev/null || { echo "ERROR: mkfs.ext4 not in PATH" >&2; exit 1; }

mkdir -p "$(dirname "$OUT")"

WORK=""
ROOTFS_DIR=""
cleanup() { [[ -n "$WORK" && -d "$WORK" ]] && rm -rf "$WORK"; }
trap cleanup EXIT

if [[ -d "$ROOTFS" ]]; then
  ROOTFS_DIR="$ROOTFS"
else
  WORK="$(mktemp -d -t tc8-system.XXXXXX)"
  ROOTFS_DIR="$WORK/rootfs"
  mkdir -p "$ROOTFS_DIR"
  echo "[+] extracting $ROOTFS -> $ROOTFS_DIR"
  case "$ROOTFS" in
    *.tar.gz|*.tgz)   tar -xzf "$ROOTFS" -C "$ROOTFS_DIR";;
    *.tar.xz)         tar -xJf "$ROOTFS" -C "$ROOTFS_DIR";;
    *.tar.zst)        tar --zstd -xf "$ROOTFS" -C "$ROOTFS_DIR";;
    *.tar.bz2)        tar -xjf "$ROOTFS" -C "$ROOTFS_DIR";;
    *.tar)            tar -xf  "$ROOTFS" -C "$ROOTFS_DIR";;
    *) echo "ERROR: unrecognized rootfs format: $ROOTFS" >&2; exit 1;;
  esac
fi

echo "[+] truncating image to $IMAGE_SIZE bytes -> $OUT"
truncate -s "$IMAGE_SIZE" "$OUT"

echo "[+] mkfs.ext4 -d $ROOTFS_DIR -L $LABEL"
mkfs.ext4 -F -L "$LABEL" -d "$ROOTFS_DIR" -T default "$OUT"

echo "[+] avbtool add_hashtree_footer (partition_size=$PART_SIZE)"
python3 "$AVBTOOL" add_hashtree_footer \
  --do_not_generate_fec \
  --partition_name system \
  --partition_size "$PART_SIZE" \
  --image "$OUT" \
  --algorithm "$ALG" \
  --key "$AVB_KEY"

ls -la "$OUT"
echo "[OK] $OUT"
