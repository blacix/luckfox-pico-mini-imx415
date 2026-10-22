#!/usr/bin/env python3
"""Resolve which sensor-mode register tables a Rockchip driver mode array actually points to.

Why: `strings` shows both `supported_modes` and `supported_modes_2lane` exist in imx415.ko,
plus register tables named ..._regs and ..._regs_2lane -- but strings cannot tell us WHICH
tables each array entry references. On our board the lane count is fixed at 2 by hardware,
so the driver will install supported_modes_2lane, and we must know whether a ~1080p binned
mode (1932x1096) survives in that set. This reads the symbol's bytes through the ELF
relocation records (in a relocatable .ko the pointers are all relocation + addend, since
section addresses are 0), which is the only trustworthy offline method -- no disassembly,
no cross toolchain, no guessing.

Usage: mode_array_relocs.py <file.ko> <symbol_name> [more symbols]
"""
import struct
import sys

SHT_RELA, SHT_REL, SHT_SYMTAB = 4, 9, 2
STT_SECTION = 3


class Elf:
    def __init__(self, path):
        self.d = open(path, "rb").read()
        assert self.d[:4] == b"\x7fELF" and self.d[4] == 1, "need a 32-bit ELF"
        e_shoff = struct.unpack_from("<I", self.d, 0x20)[0]
        e_shentsize, e_shnum, e_shstrndx = struct.unpack_from("<HHH", self.d, 0x2E)
        self.sec = {}
        for i in range(e_shnum):
            f = struct.unpack_from("<10I", self.d, e_shoff + i * e_shentsize)
            # name, type, flags, addr, offset, size, link, info, addralign, entsize
            self.sec[i] = {"name": f[0], "type": f[1], "addr": f[3], "off": f[4],
                           "size": f[5], "link": f[6], "info": f[7], "entsize": f[9]}
        shstr = self.sec[e_shstrndx]["off"]
        for s in self.sec.values():
            s["sname"] = self.str_at(shstr, s["name"])
        self.symtab = next(s for s in self.sec.values() if s["type"] == SHT_SYMTAB)
        self.strtab = self.sec[self.symtab["link"]]["off"]

    def str_at(self, base, off):
        end = self.d.index(b"\x00", base + off)
        return self.d[base + off:end].decode("utf-8", "replace")

    def syms(self):
        out = []
        esz = self.symtab.get("entsize") or 16
        n = self.symtab["size"] // esz
        for i in range(n):
            # ELF32 Sym: st_name(I) st_value(I) st_size(I) st_info(B) st_other(B) st_shndx(H)
            st_name, st_value, st_size, st_info, st_other, st_shndx = struct.unpack_from(
                "<IIIBBH", self.d, self.symtab["off"] + i * esz)
            out.append({"name": self.str_at(self.strtab, st_name), "value": st_value,
                        "size": st_size, "type": st_info & 0xF, "shndx": st_shndx})
        return out


def main():
    elf = Elf(sys.argv[1])
    want = sys.argv[2:] or ["supported_modes", "supported_modes_2lane"]
    syms = elf.syms()

    # map each relocation section to the section it applies to (sh_info).
    # NOTE: this ARM object emits SHT_REL (".rel.foo", 8-byte entries, implicit addend)
    # rather than SHT_RELA, so the addend must be read out of the data itself.
    e_shoff = struct.unpack_from("<I", elf.d, 0x20)[0]
    e_shentsize, e_shnum = struct.unpack_from("<HH", elf.d, 0x2E)
    rel_for = {}
    for i in range(e_shnum):
        f = struct.unpack_from("<10I", elf.d, e_shoff + i * e_shentsize)
        if f[1] in (SHT_RELA, SHT_REL):
            rel_for[f[7]] = (i, f[1])

    for name in want:
        sym = next((s for s in syms if s["name"] == name and s["size"] > 0), None)
        if sym is None:
            print("%s: symbol NOT FOUND" % name)
            continue
        sec = elf.sec[sym["shndx"]]
        print("\n== %s  section %s offset=0x%x size=%d bytes"
              % (name, sec["sname"], sym["value"], sym["size"]))
        if sym["shndx"] not in rel_for:
            print("   no relocation section for %s" % sec["sname"])
            continue
        ri, rtype = rel_for[sym["shndx"]]
        rs = elf.sec[ri]
        esz = rs["entsize"] or (12 if rtype == SHT_RELA else 8)
        entries = []
        for j in range(rs["size"] // esz):
            base = rs["off"] + j * esz
            r_offset, r_info = struct.unpack_from("<II", elf.d, base)
            if rtype == SHT_RELA:
                addend = struct.unpack_from("<i", elf.d, base + 8)[0]
            else:
                # implicit addend: the pointer value already sitting in the data
                addend = struct.unpack_from("<I", elf.d, sec["off"] + r_offset)[0]
            if not (sym["value"] <= r_offset < sym["value"] + sym["size"]):
                continue
            ts = syms[r_info >> 8]
            if ts["type"] == STT_SECTION:          # target is "start of a section" + addend
                tsec = elf.sec[ts["shndx"]]
                if tsec["sname"].startswith((".rodata.str", ".strtab")):
                    resolved = elf.str_at(tsec["off"], addend)
                else:
                    # The pointer aims at an object inside .rodata/.data. Named objects
                    # carry STT_OBJECT symbols, so pick the nearest one at or before the
                    # addend -- that names the register table this mode entry installs.
                    near = max((s for s in syms
                                if s["shndx"] == sym["shndx"] and s["type"] != STT_SECTION
                                and s["value"] <= addend and s["value"] + s["size"] > addend
                                and s["name"]),
                               key=lambda s: s["value"], default=None)
                    if near is None:
                        near = max((s for s in syms
                                    if s["shndx"] == sym["shndx"] and s["type"] != STT_SECTION
                                    and s["value"] <= addend and s["name"]),
                                   key=lambda s: s["value"], default=None)
                    resolved = ("%s%s" % (near["name"],
                                          "" if near["value"] == addend else "+0x%x" % (addend - near["value"]))) \
                        if near else "%s+0x%x" % (tsec["sname"], addend)
            else:
                resolved = ts["name"]
            entries.append((r_offset - sym["value"], resolved))
        stride = None
        offs = [o for o, _ in entries]
        if len(offs) > 1:
            gaps = sorted({b - a for a, b in zip(offs, offs[1:])})
            stride = gaps[0] if gaps else None
        print("   %d pointer slots%s" % (len(entries),
              ", struct stride %s bytes -> %d array entries"
              % (stride, (sym["size"] // stride) if stride else 0)))
        for off, ref in entries:
            print("     +%-3d %s" % (off, ref))


main()
