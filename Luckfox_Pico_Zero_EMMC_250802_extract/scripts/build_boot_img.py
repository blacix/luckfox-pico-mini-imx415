#!/usr/bin/env python3
"""
build_boot_img.py -- rebuild a Luckfox RV1103 "boot" partition (u-Boot FIT with external
data) so the kernel device tree declares a Sony IMX415. Built from source, offline; it never
patches anything that is already on flash.

Why a rebuilt image rather than a runtime overlay
------------------------------------------------
The kernel cannot create the I2C client for imx415 from a runtime DT overlay: this kernel has
of_i2c_register_devices() but no i2c_of_notify()/i2c_add_clients() (checked in /proc/kallsyms),
so the client set is frozen when i2c_register_adapter() runs during kernel init, before any
userspace exists. Runtime configfs overlays are inert here too (overlay status reads 0 even for
a trivial test node). The node must be in the DTB the kernel boots from.

What changes
------------
  * deletes /i2c@ff470000/sc4336@30, /i2c@ff470000/sc530ai@30 and their orphan D-PHY endpoints.
    This board has one sensor socket and it holds an IMX415: i2cdetect shows nothing at 0x30 and
    both drivers fail to probe at boot, which is why stock firmware needs video_rkcif
    clr_unready_dev. Deleting them is what frees the DTB room the IMX415 node needs.
  * adds /i2c@ff470000/imx415@37 plus /csi2-dphy0/ports/port@0/endpoint@3, data-lanes = <1 2> on
    both sides (RV1103 D-PHY has 2 lanes; imx415.ko then installs supported_modes_2lane).
  * kernel, resource and the partition tail are copied through byte for byte.
  * the FIT header is regenerated with the new fdt data-size and a recomputed sha256.

Phandles, all read out of this same DTB (see dtb/flash_fdt.dts):
  0x02 clock-controller@ff3a0000, cell 0xa5 = camera xclk out   (same as the sc3336 node uses)
  0x31 pinctrl/gpio@ff550000 (gpio3), pin 21, flag 1 = GPIO_ACTIVE_LOW
  0x32 pinctrl/mipi/mipi-refclk-out0 pin group
  0x70/0x71 new endpoint handles; the highest phandle already in the DTB is 0x6f.
"""
import hashlib
import os
import re
import struct
import subprocess
import sys

DTC = "/usr/local/bin/dtc"
PAGE = 2048
DPHY_PH, EP_PH = 0x70, 0x71

I2C_NODE = """\t\timx415@37 {
\t\t\tcompatible = "sony,imx415";
\t\t\tstatus = "okay";
\t\t\treg = <0x37>;
\t\t\tclocks = <0x02 0xa5>;
\t\t\tclock-names = "xvclk";
\t\t\treset-gpios = <0x31 0x15 0x01>;
\t\t\tpinctrl-names = "default";
\t\t\tpinctrl-0 = <0x32>;
\t\t\trockchip,camera-module-index = <0x00>;
\t\t\trockchip,camera-module-facing = "back";
\t\t\trockchip,camera-module-name = "CMK-OT2022-PX1";
\t\t\trockchip,camera-module-lens-name = "IR0147-36IRC-8M-F20";

\t\t\tport {
\t\t\t\tendpoint {
\t\t\t\t\tremote-endpoint = <0x70>;
\t\t\t\t\tdata-lanes = <0x01 0x02>;
\t\t\t\t\tphandle = <0x71>;
\t\t\t\t};
\t\t\t};
\t\t};
"""

DPHY_EP = """\t\t\t\tendpoint@3 {
\t\t\t\t\treg = <0x03>;
\t\t\t\t\tremote-endpoint = <0x71>;
\t\t\t\t\tdata-lanes = <0x01 0x02>;
\t\t\t\t\tphandle = <0x70>;
\t\t\t\t};
"""

DELETE = ["/i2c@ff470000/sc4336@30", "/i2c@ff470000/sc530ai@30",
          "/csi2-dphy0/ports/port@0/endpoint@1", "/csi2-dphy0/ports/port@0/endpoint@2"]



def run(args, data=None):
    p = subprocess.run(args, input=data, capture_output=True)
    return p.returncode, p.stdout, p.stderr


def dtb_to_dts(dtb):
    rc, out, err = run([DTC, "-I", "dtb", "-O", "dts", "-"], dtb)
    if rc:
        sys.exit("dtc -I dtb failed: " + err.decode()[:400])
    return out.decode()


def dts_to_dtb(dts):
    rc, out, err = run([DTC, "-I", "dts", "-O", "dtb", "-"], dts.encode())
    if rc:
        sys.exit("dtc -I dts FAILED:\n" + err.decode()[:3000])
    for line in err.decode().splitlines():
        if re.search(r"error|Error", line):
            print("  dtc: " + line)
    return out


def scan_nodes(text):
    """[(path, open_brace_off, close_brace_off)] for every node.

    State machine that skips quoted strings (braces inside strings must not confuse it) and
    keeps a stack, so nodes are addressable as /a/b/c the way the DTB is addressed.
    """
    nodes, stack, i, n, in_str = [], [], 0, len(text), False
    while i < n:
        c = text[i]
        if in_str:
            if c == "\\":
                i += 2
                continue
            if c == '"':
                in_str = False
            i += 1
            continue
        if c == '"':
            in_str = True
            i += 1
            continue
        if c == "{":
            j = i - 1
            while j >= 0 and text[j] in " \t\n\r":
                j -= 1
            k = j
            while k >= 0 and text[k] not in " \t\n\r":
                k -= 1
            stack.append((text[k + 1:j + 1] or "/", i))
            i += 1
            continue
        if c == "}":
            j = i + 1
            while j < n and text[j] in " \t\r":
                j += 1
            if j < n and text[j] == ";" and stack:      # node close, not a property value
                name, op = stack.pop()
                # The root pushes "/" itself; keep it out of the component list or every path
                # under the root would come out as "//i2c@ff470000/...".
                comps = [s[0] for s in stack if s[0] != "/"]
                if name != "/":
                    comps.append(name)
                nodes.append(("/" + "/".join(comps), op, i))
            i += 1
            continue
        i += 1
    return nodes


def node_span(text, path):
    for p, op, cl in scan_nodes(text):
        if p == path:
            return text.rfind("\n", 0, op) + 1, text.find(";", cl) + 1
    return None


def strip_node(text, path):
    sp = node_span(text, path)
    if not sp:
        print("  !! %-38s not found -- left alone" % path)
        return text, 0
    s, e = sp
    if text[e:e + 1] == "\n":
        e += 1
    gone = text[s:e]
    if gone.count("{") != gone.count("}"):
        sys.exit("refusing to delete %s: brace counts disagree" % path)
    print("  - %-40s -%5d B" % (path, len(gone)))
    return text[:s] + text[e:], len(gone)


def insert_before_close(text, path, block, label):
    for p, op, cl in scan_nodes(text):
        if p == path:
            line = text.rfind("\n", 0, cl) + 1
            print("  + %-40s +%5d B" % (label, len(block)))
            return text[:line] + block + text[line:]
    sys.exit("insert target %s not found" % path)


def sha_cells(data):
    """sha256 as the 8 32-bit cells a FIT header stores, rendered the way dtc renders them."""
    d = hashlib.sha256(data).digest()
    return " ".join("0x%08x" % int.from_bytes(d[i:i + 4], "big") for i in range(0, 32, 4))



def parse_images(htext):
    """{name: (data-position, data-size)} from the FIT header's /images node."""
    out = {}
    for m in re.finditer(r"\n\t\t(\w+) \{\n(.*?)\n\t\t\}", htext, re.S):
        pos = re.search(r"data-position = <0x([0-9a-fA-F]+)>", m.group(2))
        size = re.search(r"data-size = <0x([0-9a-fA-F]+)>", m.group(2))
        if pos and size:
            out[m.group(1)] = (int(pos.group(1), 16), int(size.group(1), 16))
    return out


def text_span(text, path):
    for p, op, cl in scan_nodes(text):
        if p == path:
            return text.rfind("\n", 0, op) + 1, text.find(";", cl) + 1
    return None


def patch_header(htext, fdt_size, fdt_sha):
    """Rewrite /images/fdt data-size + its sha256 value, leaving kernel/resource alone."""
    s, e = text_span(htext, "/images/fdt")
    body = htext[s:e]
    new = re.sub(r"data-size = <0x[0-9a-fA-F]+>;", "data-size = <0x%x>;" % fdt_size, body)
    new = re.sub(r"value = <0x[0-9a-fA-Fx ]+>;", "value = <%s>;" % fdt_sha, new, count=1)
    if new == body:
        sys.exit("header patch found nothing to change")
    print("  header /images/fdt: data-size -> 0x%x, sha256 recomputed" % fdt_size)
    return htext[:s] + new + htext[e:]


def main():
    src, outimg, workdir = sys.argv[1], sys.argv[2], sys.argv[3]
    os.makedirs(workdir + "/dtb", exist_ok=True)
    img = bytearray(open(src, "rb").read())
    htot = int.from_bytes(img[4:8], "big")
    htext = dtb_to_dts(bytes(img[:htot]))
    imgs = parse_images(htext)
    print("== input %s (%d bytes), FIT header %d bytes ==" % (src, len(img), htot))
    for n, (pos, size) in sorted(imgs.items(), key=lambda kv: kv[1][0]):
        print("   %-9s @0x%06x  %d bytes" % (n, pos, size))
    fpos, fsize = imgs["fdt"]
    budget = imgs["kernel"][0] - PAGE          # the DTB must not run into the kernel
    print("   DTB budget: %d bytes, in use %d, free %d" % (budget, fsize, budget - fsize))

    # Guard: the FIT header must survive a dtc round trip unchanged in meaning, or
    # regenerating it is not trustworthy and this build must not be used.
    if dtb_to_dts(dts_to_dtb(dtb_to_dts(bytes(img[:htot])))) != htext:
        sys.exit("FIT header does not survive a dtc round trip; hand-patching needed instead")
    print("== FIT header survives a dtc round trip ==")

    print("== editing the kernel device tree ==")
    dts = dtb_to_dts(bytes(img[fpos:fpos + fsize]))
    open(workdir + "/dtb/boot_fdt.orig.dts", "w").write(dts)
    for path in DELETE:
        dts, _ = strip_node(dts, path)
    dts = insert_before_close(dts, "/csi2-dphy0/ports/port@0", DPHY_EP, "dphy port@0/endpoint@3")
    dts = insert_before_close(dts, "/i2c@ff470000", I2C_NODE, "i2c4/imx415@37")
    open(workdir + "/dtb/boot_fdt.imx415.dts", "w").write(dts)

    fdt_new = dts_to_dtb(dts)
    print("== compiled DTB: %d -> %d bytes (budget %d) ==" % (fsize, len(fdt_new), budget))
    open(workdir + "/dtb/boot_fdt.imx415.dtb", "wb").write(fdt_new)
    if len(fdt_new) > budget:
        sys.exit("*** ABORT: new DTB is %d bytes over budget; no image written. ***"
                 % (len(fdt_new) - budget))

    print("== assembling the image ==")
    header = dts_to_dtb(patch_header(htext, len(fdt_new), sha_cells(fdt_new)))
    if len(header) > PAGE:
        sys.exit("new FIT header is %d bytes, does not fit in %d" % (len(header), PAGE))
    out = bytearray(img)                       # kernel, resource and tail stay byte-identical
    out[:len(header)] = header
    out[fpos:fpos + len(fdt_new)] = fdt_new
    open(outimg, "wb").write(bytes(out))
    print("   wrote %s (%d bytes)" % (outimg, len(out)))

    print("== verifying the image that was just written ==")
    chk = open(outimg, "rb").read()
    chtext = dtb_to_dts(chk[:int.from_bytes(chk[4:8], "big")])
    ok = True
    for name, (pos, size) in sorted(parse_images(chtext).items(), key=lambda kv: kv[1][0]):
        m = re.search(r"\n\t\t%s \{\n(.*?)\n\t\t\}" % name, chtext, re.S)
        claim = [int(c, 16) for c in re.search(r"value = <([0-9a-fA-Fx ]+)>", m.group(1))
                 .group(1).replace("0x", "").split()]
        real = list(struct.unpack(">8I", hashlib.sha256(chk[pos:pos + size]).digest()))
        ok &= claim == real
        print("   %-9s sha256 %s" % (name, "MATCH" if claim == real else "MISMATCH"))
    kp, ks = imgs["kernel"]
    rp, rs = imgs["resource"]
    print("   kernel bytes identical to input  : %s" % (chk[kp:kp + ks] == img[kp:kp + ks]))
    print("   resource bytes identical to input: %s" % (chk[rp:rp + rs] == img[rp:rp + rs]))
    ndts = dtb_to_dts(chk[fpos:fpos + len(fdt_new)])
    print("   imx415 node present              : %s" % ("sony,imx415" in ndts))
    print("   data-lanes = <1 2> under imx415  : %s"
          % (re.search(r"imx415@37 \{.*?data-lanes = <0x01 0x02>", ndts, re.S) is not None))
    print("   sc4336 / sc530ai removed         : %s"
          % ("sc4336" not in ndts and "sc530ai" not in ndts))
    open(outimg + ".sha256", "w").write(hashlib.sha256(bytes(out)).hexdigest()
                                       + "  " + os.path.basename(outimg) + "\n")
    print("\n" + ("IMAGE OK" if ok else "IMAGE CHECK FAILED"))
    print("sha256 " + hashlib.sha256(bytes(out)).hexdigest())


main()
