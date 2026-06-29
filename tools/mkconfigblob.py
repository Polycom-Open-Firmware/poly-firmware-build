#!/usr/bin/env python3
"""mkconfigblob.py — build a TC8 cache-partition image (see ../CONFIG-PARTITION.md).

The image is written to the START of the `cache` GPT partition over fastboot
(`fastboot flash cache <image>`); the on-device readers validate + apply it at
boot. This is the reference builder + a CLI helper; the wizard builds the same
bytes in JS.

Usage:
  mkconfigblob.py OUT KEY=value [KEY=value ...]
  mkconfigblob.py OUT --bootloader STAGE2.bin KEY=value ...   # also stage a stage-2
  mkconfigblob.py OUT --from FILE                              # KEY=value lines from a file

Layout (little-endian):
  off 0       config blob:  magic "TC8CFGv1"(8) | len u32(4) | sha256(32) | rsvd(20) | payload(N)
  off 1 MiB   bootloader header sector (only with --bootloader):
              magic "TC8BOOT1"(8) | len u32(4) | sha256(image,32) | rsvd
  off 1 MiB+512  the stage-2 image (sector-aligned)
"""
import sys, struct, hashlib

CFG_MAGIC = b"TC8CFGv1"
BL_MAGIC = b"TC8BOOT1"
BL_HDR_OFF = 1 << 20            # 1 MiB
BL_IMG_OFF = BL_HDR_OFF + 512


def cfg_blob(lines):
    payload = ("\n".join(l.rstrip("\n") for l in lines) + "\n").encode("utf-8")
    return CFG_MAGIC + struct.pack("<I", len(payload)) + hashlib.sha256(payload).digest() + b"\x00" * 20 + payload


def main(argv):
    if len(argv) < 3:
        sys.exit(__doc__)
    out, args = argv[1], argv[2:]
    bootloader = None
    if args and args[0] == "--bootloader":
        bootloader, args = args[1], args[2:]
    if args and args[0] == "--from":
        with open(args[1], encoding="utf-8") as f:
            args = [l.rstrip("\n") for l in f]

    cfg = cfg_blob(args)
    if not bootloader:
        with open(out, "wb") as f:
            f.write(cfg)
        print(f"wrote {out}: config blob {len(cfg)} B")
        return

    image = open(bootloader, "rb").read()
    buf = bytearray(BL_IMG_OFF + len(image))
    buf[0:len(cfg)] = cfg
    hdr = BL_MAGIC + struct.pack("<I", len(image)) + hashlib.sha256(image).digest() + b"\x00" * 20
    buf[BL_HDR_OFF:BL_HDR_OFF + len(hdr)] = hdr
    buf[BL_IMG_OFF:BL_IMG_OFF + len(image)] = image
    with open(out, "wb") as f:
        f.write(buf)
    print(f"wrote {out}: config {len(cfg)} B + bootloader {len(image)} B "
          f"(cache image {len(buf)} B)")


if __name__ == "__main__":
    main(sys.argv)
