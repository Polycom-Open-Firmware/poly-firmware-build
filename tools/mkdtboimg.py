#!/usr/bin/env python3
# Minimal Android DTBO image packer for the TC8 bootslot.
#
# Wraps a single .dtb into an Android DTBO container so it can be flashed to the
# stock `dtbo_X` GPT partition and consumed by NXP `boota` (the established
# Android boot path). This is the DTB carrier that pairs with a kernel+ramdisk
# boot.img — mirroring how stock Android ships its DTB in `dtbo_X`.
#
# All header/entry fields are BIG-ENDIAN per the Android DTBO spec. Layout for a
# single entry:
#
#   [32B dt_table_header][32B dt_table_entry][dtb @ 0x40]
#
# This is a focused single-entry reimplementation of AOSP mkdtboimg (Apache-2.0)
# — we only need one .dtb, so no external tool/network is required. Header layout
# matches struct dt_table_header / dt_table_entry in the AOSP libdtbo headers.
import argparse, struct, sys

MAGIC = 0xd7b7ab1e
HEADER_SIZE = 32
ENTRY_SIZE = 32
PAGE_SIZE = 2048
DT_OFFSET = HEADER_SIZE + ENTRY_SIZE   # 0x40 — start of the inner FDT

def auto(x):
    return int(x, 0)

def build(dtb):
    total_size = DT_OFFSET + len(dtb)

    # dt_table_header (all big-endian)
    hdr = struct.pack(
        ">IIIIIIII",
        MAGIC,          # magic
        total_size,     # total_size
        HEADER_SIZE,    # header_size
        ENTRY_SIZE,     # dt_entry_size
        1,              # dt_entry_count
        HEADER_SIZE,    # dt_entries_offset (32)
        PAGE_SIZE,      # page_size
        0,              # version
    )

    # dt_table_entry (all big-endian)
    entry = struct.pack(
        ">IIIIIIII",
        len(dtb),       # dt_size
        DT_OFFSET,      # dt_offset (0x40)
        0,              # id
        0,              # rev
        0, 0, 0, 0,     # custom[4]
    )

    return hdr + entry + dtb

def main():
    ap = argparse.ArgumentParser(description="minimal Android DTBO image packer (single .dtb)")
    # Accept both `create <out> --dtb X` and `--dtb X --output Y` styles.
    ap.add_argument("command", nargs="?", default=None, help="optional 'create' verb (AOSP-compatible)")
    ap.add_argument("out_pos", nargs="?", default=None, help="output path (when using the 'create' form)")
    ap.add_argument("--dtb", required=True, help="input .dtb file")
    ap.add_argument("--output", "-o", default=None, help="output .img file")
    a = ap.parse_args()

    out = a.output
    if a.command is not None and a.command != "create":
        # Treat a bare positional as the output path (no 'create' verb given).
        out = out or a.command
    elif a.command == "create":
        out = out or a.out_pos

    if not out:
        sys.exit("mkdtboimg.py: no output path (use 'create <out> --dtb X' or '--dtb X --output Y')")

    with open(a.dtb, "rb") as f:
        dtb = f.read()
    if dtb[:4] != b"\xd0\x0d\xfe\xed":
        sys.exit("mkdtboimg.py: %s is not an FDT (missing d00dfeed magic)" % a.dtb)

    img = build(dtb)
    with open(out, "wb") as f:
        f.write(img)
    print("dtbo.img: dtb=%d -> %s (%d bytes) magic=d7b7ab1e fdt@0x40" %
          (len(dtb), out, len(img)))

if __name__ == "__main__":
    main()
