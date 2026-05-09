#!/usr/bin/env bash
# kernel/build.sh — apply tc8 patches to a vanilla linux-6.6 tree, configure, and build
# Image + dtbs, then concat Image-with-dtb.
#
# USAGE
#   kernel/build.sh --linux=DIR --patches=DIR [--config=FILE] [--jobs=N] [--out=DIR]
#
# OUTPUTS (in --out dir, default ./out/kernel)
#   Image
#   imx8mm-tc8.dtb
#   Image-with-dtb         (Image || dtb concatenated)

set -euo pipefail

LINUX=""
PATCHES=""
CONFIG=""
JOBS="$(nproc)"
OUT=""
ARCH="arm64"
CROSS="${CROSS_COMPILE:-aarch64-linux-gnu-}"
DTB_NAME="imx8mm-tc8.dtb"
DTB_SUBPATH="arch/arm64/boot/dts/freescale/$DTB_NAME"

usage() {
  cat <<EOF
kernel/build.sh — patch + configure + build TC8 kernel from a vanilla 6.6 tree

USAGE
  kernel/build.sh --linux=DIR --patches=DIR [options]

REQUIRED
  --linux=DIR        Path to vanilla linux-6.6 source tree
  --patches=DIR      Path to tc8-kernel-patches/patches directory (*.patch)

OPTIONS
  --config=FILE      Kernel .config to install (default: kernel/tc8.config in this repo)
  --jobs=N           make -j (default: nproc)
  --out=DIR          Output dir for Image / dtb / Image-with-dtb (default: ./out/kernel)
  --arch=ARCH        default arm64
  --cross=PREFIX     default aarch64-linux-gnu-

ENVIRONMENT
  CROSS_COMPILE      Same as --cross
EOF
}

for arg in "$@"; do
  case "$arg" in
    --linux=*) LINUX="${arg#--linux=}";;
    --patches=*) PATCHES="${arg#--patches=}";;
    --config=*) CONFIG="${arg#--config=}";;
    --jobs=*) JOBS="${arg#--jobs=}";;
    --out=*) OUT="${arg#--out=}";;
    --arch=*) ARCH="${arg#--arch=}";;
    --cross=*) CROSS="${arg#--cross=}";;
    -h|--help) usage; exit 0;;
    *) echo "unknown arg: $arg" >&2; exit 1;;
  esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ -n "$LINUX"   ]] || { echo "ERROR: --linux=DIR required" >&2; exit 1; }
[[ -n "$PATCHES" ]] || { echo "ERROR: --patches=DIR required" >&2; exit 1; }
[[ -d "$LINUX/arch/arm64" ]] || { echo "ERROR: $LINUX does not look like a kernel tree" >&2; exit 1; }
[[ -d "$PATCHES" ]] || { echo "ERROR: patches dir not found: $PATCHES" >&2; exit 1; }
[[ -n "$CONFIG" ]] || CONFIG="$REPO_ROOT/kernel/tc8.config"
[[ -f "$CONFIG" ]] || { echo "ERROR: kernel config not found: $CONFIG" >&2; exit 1; }
[[ -n "$OUT" ]] || OUT="$REPO_ROOT/out/kernel"

mkdir -p "$OUT"
echo "[+] linux tree: $LINUX"
echo "[+] patches:    $PATCHES"
echo "[+] config:     $CONFIG"
echo "[+] out:        $OUT"
echo "[+] ARCH=$ARCH CROSS_COMPILE=$CROSS jobs=$JOBS"

cd "$LINUX"

# Apply patches idempotently — only those not already applied.
shopt -s nullglob
patch_files=("$PATCHES"/*.patch)
shopt -u nullglob

if (( ${#patch_files[@]} == 0 )); then
  echo "[!!] no .patch files found in $PATCHES — proceeding without patches"
else
  for p in "${patch_files[@]}"; do
    if git -C "$LINUX" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      if git apply --check "$p" >/dev/null 2>&1; then
        echo "[+] applying $(basename "$p")"
        git apply "$p"
      elif git apply --reverse --check "$p" >/dev/null 2>&1; then
        echo "[=] $(basename "$p") already applied — skipping"
      else
        echo "[XX] cannot cleanly apply $(basename "$p") (forward or reverse)" >&2
        exit 1
      fi
    else
      # No git tree — fall back to plain patch with idempotency check
      if patch -p1 --dry-run -R --silent < "$p" >/dev/null 2>&1; then
        echo "[=] $(basename "$p") already applied — skipping"
      else
        echo "[+] applying $(basename "$p")"
        patch -p1 < "$p"
      fi
    fi
  done
fi

# Install config
cp "$CONFIG" .config
make ARCH="$ARCH" CROSS_COMPILE="$CROSS" olddefconfig

# Build
make -j"$JOBS" ARCH="$ARCH" CROSS_COMPILE="$CROSS" Image dtbs

IMAGE_SRC="arch/$ARCH/boot/Image"
DTB_SRC="$DTB_SUBPATH"
[[ -f "$IMAGE_SRC" ]] || { echo "ERROR: $IMAGE_SRC not produced" >&2; exit 1; }
[[ -f "$DTB_SRC" ]]   || { echo "ERROR: $DTB_SRC not produced" >&2; exit 1; }

cp "$IMAGE_SRC" "$OUT/Image"
cp "$DTB_SRC"   "$OUT/$DTB_NAME"
cat "$IMAGE_SRC" "$DTB_SRC" > "$OUT/Image-with-dtb"

echo "[OK] kernel build complete:"
ls -la "$OUT/"
