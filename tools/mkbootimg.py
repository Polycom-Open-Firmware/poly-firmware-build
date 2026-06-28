#!/usr/bin/env python3
# Minimal Android boot.img *v0* packer for the TC8 bootslot.
#
# Produces an AVB-free header-v0 image: kernel in the primary slot, DTB in the
# `second` slot, empty ramdisk. Bootable by U-Boot `bootm` with
# CONFIG_ANDROID_BOOT_IMAGE (no AVB / no boota). Matches the proven C60 dual-boot
# geometry (pagesize 2048, base 0x40000000, kernel_offset 0x80000, dtb in second).
#
# This is a focused v0-only reimplementation of AOSP mkbootimg (Apache-2.0) — we
# only need v0, so no external tool/network is required. Header layout matches
# struct andr_boot_img_hdr_v0 in u-boot include/android_image.h exactly.
import argparse, hashlib, struct, sys

def filedata(p):
    if not p:
        return b""
    with open(p, "rb") as f:
        return f.read()

def pad(b, page):
    return b + b"\x00" * ((page - (len(b) % page)) % page)

def u32(x):
    return struct.pack("<I", x & 0xffffffff)

def auto(x):
    return int(x, 0)

def main():
    ap = argparse.ArgumentParser(description="minimal Android boot.img v0 packer")
    ap.add_argument("--header_version", type=auto, default=0)
    ap.add_argument("--kernel", required=True)
    ap.add_argument("--ramdisk", default=None)
    ap.add_argument("--second", default=None)            # we put the DTB here
    ap.add_argument("--pagesize", type=auto, default=2048)
    ap.add_argument("--base", type=auto, default=0x10000000)
    ap.add_argument("--kernel_offset", type=auto, default=0x00008000)
    ap.add_argument("--ramdisk_offset", type=auto, default=0x01000000)
    ap.add_argument("--second_offset", type=auto, default=0x00f00000)
    ap.add_argument("--tags_offset", type=auto, default=0x00000100)
    ap.add_argument("--cmdline", default="")
    ap.add_argument("--os_version", default=None)         # accepted, ignored (v0)
    ap.add_argument("--output", required=True)
    a = ap.parse_args()
    if a.header_version != 0:
        sys.exit("mkbootimg.py: only --header_version 0 is supported")

    page = a.pagesize
    kernel, ramdisk, second = filedata(a.kernel), filedata(a.ramdisk), filedata(a.second)

    # id[] = sha1 over (data,size) of kernel,ramdisk,second; 20-byte digest, 32-byte field.
    sha = hashlib.sha1()
    for part in (kernel, ramdisk, second):
        sha.update(part); sha.update(u32(len(part)))
    img_id = sha.digest().ljust(32, b"\x00")

    cmd = a.cmdline.encode()
    if len(cmd) > 512 + 1024:
        sys.exit("mkbootimg.py: cmdline too long")

    hdr = b"ANDROID!"
    hdr += u32(len(kernel))  + u32(a.base + a.kernel_offset)
    hdr += u32(len(ramdisk)) + u32(a.base + a.ramdisk_offset)
    hdr += u32(len(second))  + u32(a.base + a.second_offset)
    hdr += u32(a.base + a.tags_offset)
    hdr += u32(page)
    hdr += u32(0)                          # header_version = 0
    hdr += u32(0)                          # os_version
    hdr += b"\x00" * 16                    # name[16]
    hdr += cmd[:512].ljust(512, b"\x00")   # cmdline[512]
    hdr += img_id                          # id[8] (32 bytes)
    hdr += cmd[512:].ljust(1024, b"\x00")  # extra_cmdline[1024]

    out = pad(hdr, page) + pad(kernel, page)
    if ramdisk:
        out += pad(ramdisk, page)
    if second:
        out += pad(second, page)

    with open(a.output, "wb") as f:
        f.write(out)
    print("boot.img v0: kernel=%d ramdisk=%d second=%d page=%d -> %s (%d bytes)" %
          (len(kernel), len(ramdisk), len(second), page, a.output, len(out)))

if __name__ == "__main__":
    main()
