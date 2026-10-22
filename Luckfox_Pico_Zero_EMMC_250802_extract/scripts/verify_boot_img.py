#!/usr/bin/env python3
"""Independent check of a rebuilt Luckfox RV1103 boot partition, using libfdt (fdtget) rather
than the parser that built it -- a build script grading its own work proves little.

  verify_boot_img.py <image> [<original-image>]

Reports the FIT layout, recomputes every hash, and -- when an original is given -- shows exactly
how many bytes differ and confirms the kernel/resource regions and everything past them survived.
"""
import hashlib
import re
import struct
import subprocess
import sys

FDTGET = "/usr/local/bin/fdtget"


def get(header, path, prop):
    p = subprocess.run([FDTGET, header, path, prop], capture_output=True)
    if p.returncode:
        return None
    return p.stdout.decode().strip()


def main():
    img_path = sys.argv[1]
    orig = sys.argv[2] if len(sys.argv) > 2 else None
    d = open(img_path, "rb").read()
    hlen = int.from_bytes(d[4:8], "big")
    hdr = "/tmp/_vhdr.dtb"
    open(hdr, "wb").write(d[:hlen])
    print("%s: %d bytes, FIT header FDT is %d bytes" % (img_path, len(d), hlen))

    # fdtget renders a byte-array property as signed decimals, which is useless for comparing
    # against hashlib's hex; read the cells from the dtc text instead and compare per cell.
    htext = subprocess.run(["/usr/local/bin/dtc", "-I", "dtb", "-O", "dts", hdr],
                           capture_output=True).stdout.decode()

    def cells(image):
        m = re.search(r"\n\t\t" + image + r" \{(.*?)\n\t\t\}", htext, re.S)
        if not m:
            return None
        body = m.group(1)
        pos = re.search(r"data-position = <0x([0-9a-fA-F]+)>", body)
        size = re.search(r"data-size = <0x([0-9a-fA-F]+)>", body)
        val = re.search(r"value = <([0-9a-fA-Fx ]+)>", body)
        if not (pos and size):
            return None
        return (int(pos.group(1), 16), int(size.group(1), 16),
                [int(c, 16) for c in val.group(1).replace("0x", "").split()] if val else None)

    ok = True
    for img in ("fdt", "kernel", "resource"):
        got = cells(img)
        if got is None:
            print("  %-9s absent from the header" % img)
            ok = False
            continue
        pos, size, want = got
        real = list(struct.unpack(">8I", hashlib.sha256(d[pos:pos + size]).digest()))
        match = want is not None and want == real
        ok &= match
        print("  %-9s @0x%06x  %8d bytes  sha256 %s" %
              (img, pos, size, "MATCH" if match else "MISMATCH"))
        if want is not None and not match:
            print("      header: %s" % " ".join("%08x" % c for c in want))
            print("      actual: %s" % " ".join("%08x" % c for c in real))

    fdt_pos, fdt_size, _ = cells("fdt")
    kern_pos = cells("kernel")[0]
    print("  DTB budget before the kernel: %d, used %d, spare %d"
          % (kern_pos - fdt_pos, fdt_size, kern_pos - fdt_pos - fdt_size))

    dtb = subprocess.run(["/usr/local/bin/dtc", "-I", "dtb", "-O", "dts", "-"],
                         input=d[fdt_pos:fdt_pos + fdt_size], capture_output=True).stdout.decode()
    print("  device tree contents:")
    for needle in ('compatible = "sony,imx415"', "reg = <0x37>", "data-lanes = <0x01 0x02>",
                   'rockchip,camera-module-name = "CMK-OT2022-PX1"',
                   'rockchip,camera-module-lens-name = "IR0147-36IRC-8M-F20"'):
        print("     %-58s %d" % (needle, dtb.count(needle)))
    for gone in ("sc4336", "sc530ai"):
        print("     %-58s %d (want 0)" % ("leftover %s" % gone, dtb.count(gone)))

    if orig:
        o = open(orig, "rb").read()
        diff = sum(1 for a, b in zip(o, d) if a != b)
        print("  vs %s:" % orig)
        print("     differing bytes          : %d of %d" % (diff, len(d)))
        print("     identical from kernel on : %s" % (o[kern_pos:] == d[kern_pos:]))
        print("     same length              : %s" % (len(o) == len(d)))
    print("\n%s" % ("VERIFIED" if ok else "PROBLEMS FOUND"))
    return 0 if ok else 1


sys.exit(main())
