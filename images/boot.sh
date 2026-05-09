#!/usr/bin/env bash
# images/boot.sh — pack Image-with-dtb (+ optional initramfs) into an Android boot.img
# and add an AVB hash footer.
#
# USAGE
#   images/boot.sh --kernel=PATH --profile=nfs|emmc [--initramfs=PATH] \
#                  [--avb-key=KEY] [--out=FILE] [--partition-size=BYTES]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=cmdlines.sh
source "$REPO_ROOT/images/cmdlines.sh"

KERNEL=""
PROFILE=""
INITRAMFS=""
AVB_KEY="${TC8_AVB_KEY:-}"
OUT=""
PART_SIZE="50331648"   # 48 MiB — matches stock boot_a/_b
BASE="0x40000000"
PAGESIZE="2048"
HEADER_VERSION="0"
ALG="SHA256_RSA4096"

usage() {
  cat <<EOF
images/boot.sh — build + AVB-sign boot.img

USAGE
  images/boot.sh --kernel=PATH --profile={nfs|emmc} [options]

REQUIRED
  --kernel=PATH         Image-with-dtb (Image||dtb concatenated) from kernel/build.sh
  --profile={nfs|emmc}  Selects KERNEL_CMDLINE from profiles/<name>.env
                        (or pass a path to a custom .env)

OPTIONS
  --initramfs=PATH      Optional initramfs.cpio.gz (eMMC profile uses this if present)
  --avb-key=KEY         AVB signing key (default: \$TC8_AVB_KEY)
  --out=FILE            Output path (default: ./out/boot.img)
  --partition-size=N    AVB partition size (default: $PART_SIZE)
  -h, --help            Show this help
EOF
}

for arg in "$@"; do
  case "$arg" in
    --kernel=*) KERNEL="${arg#--kernel=}";;
    --profile=*) PROFILE="${arg#--profile=}";;
    --initramfs=*) INITRAMFS="${arg#--initramfs=}";;
    --avb-key=*) AVB_KEY="${arg#--avb-key=}";;
    --out=*) OUT="${arg#--out=}";;
    --partition-size=*) PART_SIZE="${arg#--partition-size=}";;
    -h|--help) usage; exit 0;;
    *) echo "unknown arg: $arg" >&2; exit 1;;
  esac
done

[[ -n "$KERNEL"  ]] || { echo "ERROR: --kernel= required" >&2; exit 1; }
[[ -n "$PROFILE" ]] || { echo "ERROR: --profile= required" >&2; exit 1; }
[[ -f "$KERNEL"  ]] || { echo "ERROR: kernel not found: $KERNEL" >&2; exit 1; }
[[ -n "$AVB_KEY" ]] || { echo "ERROR: --avb-key= or TC8_AVB_KEY required" >&2; exit 1; }
[[ -f "$AVB_KEY" ]] || { echo "ERROR: avb key not found: $AVB_KEY" >&2; exit 1; }
[[ -n "$OUT" ]] || OUT="$REPO_ROOT/out/boot.img"

load_profile_cmdline "$PROFILE"
echo "[+] profile=$PROFILE"
echo "[+] cmdline=$KERNEL_CMDLINE"

MKBOOTIMG="$REPO_ROOT/vendored/mkbootimg/mkbootimg.py"
AVBTOOL="$REPO_ROOT/vendored/avb/avbtool.py"
[[ -f "$MKBOOTIMG" ]] || { echo "ERROR: $MKBOOTIMG missing" >&2; exit 1; }
[[ -f "$AVBTOOL"   ]] || { echo "ERROR: $AVBTOOL missing"   >&2; exit 1; }

mkdir -p "$(dirname "$OUT")"

mkbootargs=(
  --kernel "$KERNEL"
  --cmdline "$KERNEL_CMDLINE"
  --base "$BASE"
  --pagesize "$PAGESIZE"
  --header_version "$HEADER_VERSION"
  -o "$OUT"
)
if [[ -n "$INITRAMFS" ]]; then
  [[ -f "$INITRAMFS" ]] || { echo "ERROR: initramfs not found: $INITRAMFS" >&2; exit 1; }
  mkbootargs+=( --ramdisk "$INITRAMFS" )
  echo "[+] embedding initramfs: $INITRAMFS"
fi

echo "[+] mkbootimg -> $OUT"
python3 "$MKBOOTIMG" "${mkbootargs[@]}"

echo "[+] avbtool add_hash_footer (partition_size=$PART_SIZE)"
python3 "$AVBTOOL" add_hash_footer \
  --partition_name boot \
  --partition_size "$PART_SIZE" \
  --image "$OUT" \
  --algorithm "$ALG" \
  --key "$AVB_KEY"

ls -la "$OUT"
echo "[OK] $OUT"
