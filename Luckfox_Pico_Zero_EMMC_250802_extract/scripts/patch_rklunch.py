#!/usr/bin/env python3
"""Add the missing imx415 branch to Luckfox's RkLunch.sh rkipc-ini selector.

The shipped selector walks lsmod and, for every sensor module it recognises, does
    ln -s -f /oem/usr/share/rkipc-<n>w.ini $default_rkipc_ini
in sequence, so the LAST match wins. It knows sc530ai / sc4336 / sc3336 only. With imx415
loaded and none of those matched it falls through to

    if [ ! -f "$default_rkipc_ini" ]; then echo "Error: not found rkipc.ini !!!"; exit -1; fi

and rkipc never starts -- which is what would happen on this board even today. The imx415
block therefore has to be appended after the sc3336 block, still inside the
    if [ ! -f "/oem/usr/share/rkipc.ini" ]; then
guard, because sc3336.ko is always loaded by insmod_ko.sh and would otherwise win.

The result is checked with "sh -n" before it is written out.
"""
import re
import subprocess
import sys

src, dst = sys.argv[1], sys.argv[2]
ini = sys.argv[3] if len(sys.argv) > 3 else "rkipc-imx415-720p.ini"

text = open(src).read()
if "grep imx415" in text:
    print("RkLunch.sh already carries an imx415 branch; nothing to do")
    sys.exit(0)

lines = text.split("\n")
# find the sc3336 "ln -s" line, then the "\t\tfi" that closes its if-block
try:
    i = next(n for n, l in enumerate(lines)
             if l.strip().startswith("ln -s -f /oem/usr/share/rkipc-300w.ini"))
except StopIteration:
    sys.exit("anchor line (rkipc-300w.ini symlink) not found -- not a RkLunch.sh I know")
j = next((n for n in range(i + 1, len(lines)) if lines[n] == "\t\tfi"), None)
if j is None:
    sys.exit("closing 'fi' of the sc3336 block not found")
if lines[j + 1] != "\tfi":
    sys.exit("unexpected structure after the sc3336 block (expected the guard's 'fi'); refusing")

block = ["\t\tlsmod | grep imx415",
         "\t\tif [ $? -eq 0 ]; then",
         "\t\t\tln -s -f /oem/usr/share/%s $default_rkipc_ini" % ini,
         "\t\tfi"]
out = lines[:j + 1] + block + lines[j + 1:]
new = "\n".join(out)

open(dst, "w").write(new)
rc = subprocess.run(["sh", "-n", dst], capture_output=True)
print("sh -n on the patched script: %s" % ("OK" if rc.returncode == 0 else rc.stderr.decode()[:300]))
print("inserted after line %d:" % (j + 1))
for l in block:
    print("   " + repr(l))
print("\nguard / selector / tail audit:")
for pat in (r'if \[ ! -f "/oem/usr/share/rkipc.ini" \]; then', r"grep imx415",
            r"rkipc-imx415-720p\.ini \$default_rkipc_ini", r'cp \$default_rkipc_ini \$rkipc_ini'):
    print("   %-58s %d" % (pat, len(re.findall(pat, new, re.M))))
sys.exit(0 if rc.returncode == 0 else 1)
