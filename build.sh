#!/usr/bin/env bash
# build.sh — top-level pipeline: build kernel, then boot/system/dtbo/vbmeta images.
#
# USAGE
#   ./build.sh --linux=/path/to/linux-6.6 \
#              --patches=/path/to/tc8-kernel-patches/patches \
#              --rootfs=/path/to/rootfs.tar.gz \
#              [--initramfs=/path/to/initramfs.cpio.gz] \
#              --profile={nfs|emmc} \
#              [--avb-key=$TC8_AVB_KEY] \
#              [--out=./out] \
#              [--skip-kernel]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"

LINUX=""; PATCHES=""; ROOTFS=""; INITRAMFS=""; PROFILE=""
AVB_KEY="${TC8_AVB_KEY:-}"
OUT="$REPO_ROOT/out"
SKIP_KERNEL=0
JOBS="$(nproc)"

usage() {
  cat <<EOF
build.sh — full TC8 firmware build (kernel + boot + system + dtbo + vbmeta)

USAGE
  ./build.sh --linux=DIR --patches=DIR --rootfs=PATH --profile={nfs|emmc} [options]

REQUIRED
  --linux=DIR        Vanilla linux-6.6 source tree
  --patches=DIR      tc8-kernel-patches/patches directory
  --rootfs=PATH      rootfs tarball or directory
  --profile=NAME     nfs | emmc | path/to/custom.env

OPTIONS
  --initramfs=PATH   initramfs.cpio.gz (used by emmc profile if provided)
  --avb-key=KEY      AVB key file (default: \$TC8_AVB_KEY)
  --out=DIR          output dir (default: ./out)
  --skip-kernel      do not rebuild kernel (use existing out/kernel/Image-with-dtb)
  --jobs=N           parallelism for kernel build (default: nproc)
  -h, --help         Show this help
EOF
}

for arg in "$@"; do
  case "$arg" in
    --linux=*) LINUX="${arg#--linux=}";;
    --patches=*) PATCHES="${arg#--patches=}";;
    --rootfs=*) ROOTFS="${arg#--rootfs=}";;
    --initramfs=*) INITRAMFS="${arg#--initramfs=}";;
    --profile=*) PROFILE="${arg#--profile=}";;
    --avb-key=*) AVB_KEY="${arg#--avb-key=}";;
    --out=*) OUT="${arg#--out=}";;
    --skip-kernel) SKIP_KERNEL=1;;
    --jobs=*) JOBS="${arg#--jobs=}";;
    -h|--help) usage; exit 0;;
    *) echo "unknown arg: $arg" >&2; exit 1;;
  esac
done

[[ -n "$ROOTFS"  ]] || { echo "ERROR: --rootfs= required" >&2; exit 1; }
[[ -n "$PROFILE" ]] || { echo "ERROR: --profile= required" >&2; exit 1; }
[[ -n "$AVB_KEY" ]] || { echo "ERROR: --avb-key= or TC8_AVB_KEY required" >&2; exit 1; }
[[ -f "$AVB_KEY" ]] || { echo "ERROR: AVB key not found: $AVB_KEY" >&2; exit 1; }

if [[ $SKIP_KERNEL -ne 1 ]]; then
  [[ -n "$LINUX"   ]] || { echo "ERROR: --linux= required (or pass --skip-kernel)" >&2; exit 1; }
  [[ -n "$PATCHES" ]] || { echo "ERROR: --patches= required (or pass --skip-kernel)" >&2; exit 1; }
fi

mkdir -p "$OUT"
export TC8_AVB_KEY="$AVB_KEY"

KERNEL_OUT="$OUT/kernel"
KIMG="$KERNEL_OUT/Image-with-dtb"
DTB="$KERNEL_OUT/imx8mm-tc8.dtb"

if [[ $SKIP_KERNEL -ne 1 ]]; then
  echo "===> [1/5] kernel build"
  "$REPO_ROOT/kernel/build.sh" --linux="$LINUX" --patches="$PATCHES" \
    --jobs="$JOBS" --out="$KERNEL_OUT"
else
  echo "===> [1/5] kernel build SKIPPED (--skip-kernel)"
  [[ -f "$KIMG" ]] || { echo "ERROR: $KIMG missing; cannot --skip-kernel" >&2; exit 1; }
  [[ -f "$DTB"  ]] || { echo "ERROR: $DTB missing; cannot --skip-kernel"  >&2; exit 1; }
fi

echo "===> [2/5] boot.img"
boot_args=( --kernel="$KIMG" --profile="$PROFILE" --avb-key="$AVB_KEY" --out="$OUT/boot.img" )
[[ -n "$INITRAMFS" ]] && boot_args+=( --initramfs="$INITRAMFS" )
"$REPO_ROOT/images/boot.sh" "${boot_args[@]}"

echo "===> [3/5] system.img"
"$REPO_ROOT/images/system.sh" --rootfs="$ROOTFS" --avb-key="$AVB_KEY" --out="$OUT/system.img"

echo "===> [4/5] dtbo.img"
"$REPO_ROOT/images/dtbo.sh" --dtb="$DTB" --avb-key="$AVB_KEY" --out="$OUT/dtbo.img"

echo "===> [5/5] vbmeta.img"
"$REPO_ROOT/images/vbmeta.sh" \
  --boot="$OUT/boot.img" --system="$OUT/system.img" --dtbo="$OUT/dtbo.img" \
  --avb-key="$AVB_KEY" --out="$OUT/vbmeta.img"

echo "===> SHA256SUMS"
( cd "$OUT" && sha256sum boot.img dtbo.img system.img vbmeta.img > SHA256SUMS && cat SHA256SUMS )

echo "[OK] all artifacts in $OUT"
