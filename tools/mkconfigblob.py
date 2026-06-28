#!/usr/bin/env python3
"""mkconfigblob.py — build a TC8 autoconfigure blob (see ../CONFIG-PARTITION.md).

The blob is written to the START of the `cache` GPT partition over fastboot
(`fastboot flash cache <blob>`); the on-device reader
(rootfs/etc/tc8-config/apply-config.sh) validates + applies it at boot. This is
the reference builder + a CLI provisioning helper; the wizard builds the same
bytes in JS.

Usage:
  mkconfigblob.py OUT.bin KEY=value [KEY=value ...]
  mkconfigblob.py OUT.bin --from FILE      # KEY=value lines from a file

Layout (little-endian): magic "TC8CFGv1"(8) | len u32(4) | sha256(32) | rsvd(20) | payload(N)
"""
import sys, struct, hashlib

MAGIC = b"TC8CFGv1"


def build(lines):
    payload = ("\n".join(l.rstrip("\n") for l in lines) + "\n").encode("utf-8")
    header = MAGIC + struct.pack("<I", len(payload)) + hashlib.sha256(payload).digest() + b"\x00" * 20
    assert len(header) == 64
    return header + payload


def main(argv):
    if len(argv) < 3:
        sys.exit(__doc__)
    out, rest = argv[1], argv[2:]
    if rest[0] == "--from":
        with open(rest[1], encoding="utf-8") as f:
            lines = [l.rstrip("\n") for l in f]
    else:
        lines = rest
    blob = build(lines)
    with open(out, "wb") as f:
        f.write(blob)
    print(f"wrote {out}: {len(blob)} bytes (64 header + {len(blob) - 64} payload)")


if __name__ == "__main__":
    main(sys.argv)
