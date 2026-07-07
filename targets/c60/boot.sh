# targets/c60/boot.sh — C60 boot recipe: `booti` + rootfs in system_a.
# The C60 boot model differs from TC8's boota A/B slots by design (clean
# separation, not a forced abstraction). Today the C60 path lives in
# c60-firmware-build; folding it here is the M6 boot-convergence step.
# Interface contract (same as tc8/boot.sh): produces the target's flashable
# boot artifacts into $OUT and sets BOOT_SUM_FILES.
pack_boot() {
    echo "===> [boot:booti] C60 recipe not yet folded into the shared composer" >&2
    echo "     (C60 boots via booti + system_a; see c60-firmware-build. M6 TODO.)" >&2
    return 1
}
