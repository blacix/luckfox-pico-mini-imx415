#!/usr/bin/env python3
"""Map dtc-decompiled .dts phandle numbers to the node paths that own them.

Overlay authoring needs this: the Pico Zero imx415 node refers to its xvclk, gpio bank,
pinctrl group and dphy endpoint by opaque <0xNN> phandles, and those numbers are
different in our board's live DT. This walks the indented text dtc emits, tracks node
nesting, and reports which node carries each phandle.

Usage: phandle_map.py <file.dts> [hex_or_dec_phandle ...]   (no handles = print all)
"""
import re
import sys

PROP = re.compile(r'^\s*(?:/[*/]|$)')


def walk(path):
    node_stack = []          # list of (indent, name)
    map_ = {}
    with open(path, "r", errors="replace") as fh:
        for raw in fh:
            line = raw.rstrip("\n")
            stripped = line.strip()
            if not stripped or PROP.match(stripped):
                continue
            indent = len(line) - len(line.lstrip("\t"))
            m = re.match(r'^([A-Za-z0-9_.@{},/&-]+(?:\s*\{)?|/)\s*\{$', stripped)
            if m and not stripped.startswith("}"):
                name = m.group(1).strip()
                while node_stack and node_stack[-1][0] >= indent:
                    node_stack.pop()
                node_stack.append((indent, name))
                continue
            if stripped.startswith("}"):
                while node_stack and node_stack[-1][0] >= indent:
                    node_stack.pop()
                continue
            p = re.match(r'^phandle = <(0x[0-9a-fA-F]+|\d+)>;$', stripped)
            if p:
                val = int(p.group(1), 0)
                parts = [n for _, n in node_stack]
                path_s = "/" + "/".join(x for x in parts if x not in ("/", "{", "}"))
                map_.setdefault(val, path_s)
    return map_


def pretty(p):
    return re.sub(r'/node@([0-9a-f]+)', r'/\1', p.replace("/.", "/"))


dts = sys.argv[1]
wanted = [int(a, 0) for a in sys.argv[2:]]
handles = walk(dts)
print("%s: %d phandles resolved" % (dts.split("/")[-1], len(handles)))
sel = wanted if wanted else sorted(handles)
for h in sel:
    if h in handles:
        print("  <0x%02x> (%3d) = %s" % (h, h, pretty(handles[h])))
    else:
        print("  <0x%02x> (%3d) = NOT FOUND in this DT" % (h, h))
