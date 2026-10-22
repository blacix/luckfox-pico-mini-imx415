#!/usr/bin/env python3
"""Carve every Flattened Device Tree blob out of a Rockchip boot.img.

boot.img on RV1103/RV1106 is a container (u-boot image / kernel / resource.img), so the
real DTB is not at offset 0 even though `file` sees an FDT magic there. This scans for
the d00dfeed magic on 4-byte boundaries, trusts the totalsize field, sanity-checks it,
skips blobs nested inside an already-carved larger blob, and writes dtb/<base>_N.dtb.

Usage: carve_dtb.py <image> <out_dir_prefix>
"""
import os
import struct
import sys

MAGIC = b"\xd0\x0d\xfe\xed"


def carve(image, prefix):
    with open(image, "rb") as fh:
        data = fh.read()
    found, taken = [], []
    off = 0
    while True:
        i = data.find(MAGIC, off)
        if i < 0 or i + 8 > len(data) or i % 4:
            break
        size = struct.unpack_from(">I", data, i + 4)[0]
        plausible = 32 <= size <= 8 * 1024 * 1024 and size % 4 == 0 and i + size <= len(data)
        nested = any(s <= i and i + size <= s + e for s, e in taken)
        if plausible and not nested:
            found.append((i, size))
            taken.append((i, size))
            off = i + size          # a real DTB: skip past it, do not match inside it
        else:
            off = i + 4             # false magic or nested sub-blob: keep scanning
    print("%s: %d candidate DTB(s)" % (os.path.basename(image), len(found)))
    os.makedirs(os.path.dirname(prefix) or ".", exist_ok=True)
    for n, (i, size) in enumerate(found):
        out = "%s_%d.dtb" % (prefix, n)
        with open(out, "wb") as fh:
            fh.write(data[i:i + size])
        # struct_region / name block hints straight from the fdt_header
        structs, strsz, mem_rsv, type_off, name_off, pa = struct.unpack_from(">6I", data, i + 8)
        print("   [%d] off=0x%08x size=%-8d structs=%-6d strings=%-5d name_block@%d -> %s"
              % (n, i, size, structs, strsz, name_off, os.path.basename(out)))
    return found


if __name__ == "__main__":
    carve(sys.argv[1], sys.argv[2])
