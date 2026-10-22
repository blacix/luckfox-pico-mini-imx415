#!/usr/bin/env python3
"""Minimal ELF section-header dumper (no external deps).

Used to answer, offline and without a cross toolchain on macOS:
  * is this .ko 32-bit ARM relocatable?
  * does it carry a __versions section -> CONFIG_MODVERSIONS / symbol CRC pinning?
Usage: elf_sections.py FILE [FILE...]
"""
import struct
import sys

SHT = {0: "NULL", 1: "PROGBITS", 2: "SYMTAB", 3: "STRTAB", 4: "RELA", 6: "DYNAMIC",
       8: "NOBITS", 9: "REL", 14: "DYNSYM", 0x6ffffffb: "VERSYM", 0x6ffffff0: "VERSYM"}


def dump(path):
    with open(path, "rb") as fh:
        data = fh.read()
    if data[:4] != b"\x7fELF":
        print("%s: NOT AN ELF FILE" % path)
        return
    ei_class, ei_data, ei_machine = data[4], data[5], struct.unpack_from("<H", data, 18)[0]
    is64 = ei_class == 2
    little = ei_data == 1
    endian = "<" if little else ">"
    e_type = struct.unpack_from(endian + "H", data, 16)[0]
    # e_shoff lives at 0x20 in ELF32 but 0x28 in ELF64
    shoff = struct.unpack_from(endian + ("Q" if is64 else "I"), data, 0x28 if is64 else 0x20)[0]
    shentsize = struct.unpack_from(endian + "H", data, 0x3A if is64 else 0x2E)[0]
    shnum = struct.unpack_from(endian + "H", data, 0x3C if is64 else 0x30)[0]
    shstrndx = struct.unpack_from(endian + "H", data, 0x3E if is64 else 0x32)[0]

    arch = {40: "ARM(32-bit)", 183: "AArch64", 3: "x86", 62: "x86-64"}.get(ei_machine, "machine %d" % ei_machine)
    types = {1: "REL relocatable", 2: "EXEC", 3: "DYN", 4: "CORE"}
    print("== %s" % path)
    print("   %s %s, %s endian, %s, %d section headers"
          % ("ELF64" if is64 else "ELF32", arch, "little" if little else "big",
             types.get(e_type, e_type), shnum))

    def shdr(i):
        off = shoff + i * shentsize
        if is64:
            # name, type, flags(8), addr, offset, size
            f = struct.unpack_from(endian + "IIQQQQIIQQ", data, off)
            return {"name": f[0], "type": f[1], "addr": f[3], "off": f[4], "size": f[5]}
        # ELF32: name, type, flags, addr, offset, size  (offset is field index 4, not 3)
        f = struct.unpack_from(endian + "IIIIIIIIII", data, off)
        return {"name": f[0], "type": f[1], "addr": f[3], "off": f[4], "size": f[5]}

    strtab = shdr(shstrndx)
    base = strtab["off"]

    def nm(o):
        end = data.index(b"\x00", base + o)
        return data[base + o:end].decode("ascii", "replace")

    names = [nm(shdr(i)["name"]) for i in range(shnum)]
    print("   sections: %s" % ", ".join(n for n in names if n))
    for want in ("__versions", "__mcount_loc", ".modinfo", ".note.gnu.build-id"):
        if want in names:
            s = shdr(names.index(want))
            print("   >>> FOUND %s  size=%d bytes (~%d pinned symbols)"
                  % (want, s["size"], s["size"] // (64 if is64 else 60)))
    if "__versions" not in names:
        print("   >>> NO __versions section: this kernel was built WITHOUT CONFIG_MODVERSIONS")
    if ".modinfo" in names:
        s = shdr(names.index(".modinfo"))
        blob = data[s["off"]:s["off"] + s["size"]].decode("utf-8", "replace")
        for line in blob.split("\0"):
            if line.startswith(("vermagic", "name", "depends", "description", "author")):
                print("   .modinfo: %s" % line)


for arg in sys.argv[1:]:
    try:
        dump(arg)
    except Exception as exc:  # keep going over a batch
        print("%s: ERROR %s" % (arg, exc))
