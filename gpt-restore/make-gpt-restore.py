#!/usr/bin/env python3
# Build tc8-gpt-restore.simg — a full-disk Android sparse image that restores the
# TC8 eMMC partition table (GPT) on a unit whose table was nuked, WITHOUT touching
# anything else on the disk:
#   - RAW chunk: primary GPT (protective MBR + header + entries) at LBA 0..33
#   - DONT_CARE chunk: the entire middle (LBA 34 .. last-34) — so the U-Boot env at
#     0x400000 (MAC/serial), the raw stage-2 slot, and every partition's data are
#     PRESERVED, not zeroed.
#   - RAW chunk: backup GPT (entries + header) at the last 33 LBAs.
#
# Source GPT was captured from a healthy unit (gpt-primary.bin / gpt-backup.bin);
# all four GPT CRC32s validated. Flash to a GPT-independent raw whole-disk fastboot
# target (see README) — the named partitions don't exist yet on a nuked unit.
#
# blk_sz MUST be 512: the primary GPT is 34 sectors (not 4 KiB-aligned), and a
# 512-granular DONT_CARE is what lets us preserve the 4 MiB env exactly.
import struct, os

SECTOR = 512
TOTAL_SECTORS = 30535680  # mmcblk2 = 15267840 KiB * 2 (14.56 GiB)
HERE = os.path.dirname(os.path.abspath(__file__))

prim = open(os.path.join(HERE, "gpt-primary.bin"), "rb").read()  # LBA 0..33
back = open(os.path.join(HERE, "gpt-backup.bin"), "rb").read()   # last 33 LBAs
assert len(prim) == 34 * SECTOR and prim[512:520] == b"EFI PART", "bad primary GPT"
assert len(back) == 33 * SECTOR, "bad backup GPT"

np, nb = 34, 33
ndc = TOTAL_SECTORS - np - nb
RAW, DONT_CARE = 0xCAC1, 0xCAC3

out = struct.pack("<IHHHHIIII", 0xED26FF3A, 1, 0, 28, 12, SECTOR, TOTAL_SECTORS, 3, 0)
out += struct.pack("<HHII", RAW, 0, np, 12 + len(prim)) + prim
out += struct.pack("<HHII", DONT_CARE, 0, ndc, 12)
out += struct.pack("<HHII", RAW, 0, nb, 12 + len(back)) + back

path = os.path.join(HERE, "tc8-gpt-restore.simg")
open(path, "wb").write(out)
print(f"wrote {path}: {len(out)} bytes on-wire, expands to {TOTAL_SECTORS*SECTOR} bytes")
