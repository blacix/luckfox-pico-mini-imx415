#!/usr/bin/env python3
"""Derive a 720p rkipc ini from the Luckfox Pico Zero's imx415 (5M) ini.

Everything that is sensor/ISP tuning -- the whole [isp*] block, IQ handling, H.264 profile,
QP/rate-control tables, ircut gpios, smart-codec settings -- is carried over untouched, because
that is the reference tuning for this sensor. Only the geometry and rate keys change:

  [video.0]    buffer_size 3840*2160 -> 1280*720 (the ini comments it as "w * h")
               max_width/max_height, width/height  3040x1710 -> 1280x720
               src/dst_frame_rate_num 20 -> 30            gop 50 -> 30
  [video.1]    2560x1440 -> 1280x720   (venc_1 is disabled, kept <= source anyway)
  [video.2]    960x540   -> 640x360    (venc_2 is disabled)
  [video.jpeg] 1920x1080 -> 1280x720   (enable_jpeg = 1, so it must not exceed the source)

Why 1280x720: with data-lanes = <1 2> the driver installs supported_modes_2lane, whose only
sub-8MP entry is imx415_linear_12bit_1284x720_2376M_regs_2lane (resolved out of the module's
relocation records). The 1932x1096 2x2-binned mode the bring-up doc asks for exists only in the
4-lane array, so on 2 lanes 720p comes from that 1284x720 mode, with the ISP doing the
1284 -> 1280 horizontal scale.
"""
import re
import sys

src, dst = sys.argv[1], sys.argv[2]
text = open(src).read()

# Line-anchored on purpose: a plain substring test would also match "max_width = 3040" when
# looking for "width = 3040" and silently edit the wrong key. Each pattern must match exactly
# once, or the source ini is not the one this adapter was written against -- refusing is better
# than half-editing a tuning file.
REPL = [
    (r"^buffer_size = 8294400", "buffer_size = 921600"),
    (r"^max_width = 3040", "max_width = 1280"),
    (r"^max_height = 1710", "max_height = 720"),
    (r"^width = 3040", "width = 1280"),
    (r"^height = 1710", "height = 720"),
    (r"^src_frame_rate_num = 20", "src_frame_rate_num = 30"),
    (r"^dst_frame_rate_num = 20", "dst_frame_rate_num = 30"),
    (r"^gop = 50", "gop = 30"),
    (r"^max_width = 2560", "max_width = 1280"),
    (r"^max_height = 1440", "max_height = 720"),
    (r"^width = 2560", "width = 1280"),
    (r"^height = 1440", "height = 720"),
    (r"^max_width = 960", "max_width = 640"),
    (r"^max_height = 540", "max_height = 360"),
    (r"^width = 960", "width = 640"),
    (r"^height = 540", "height = 360"),
    (r"^width = 1920", "width = 1280"),
    (r"^height = 1080", "height = 720"),
]

for pat, new in REPL:
    n = len(re.findall(pat, text, re.M))
    if n != 1:
        sys.exit("expected %r exactly once, found %d -> refusing to edit" % (pat, n))

for pat, new in REPL:
    text = re.sub(pat, new, text, count=1, flags=re.M)
    print("  %-34s -> %s" % (pat.lstrip("^"), new))

open(dst, "w").write(text)
print("\nwrote " + dst)
for sec in ("video.0", "video.1", "video.2", "video.jpeg"):
    m = re.search(r"\[" + sec + r"\]\n(.*?)(?=\n\[|\Z)", text, re.S)
    if m:
        keys = dict(re.findall(r"^(width|height|gop|buffer_size) = ([0-9]+)", m.group(1), re.M))
        print("  [%-10s] %s" % (sec, " ".join("%s=%s" % (k, keys[k]) for k in
                                              sorted(keys) if k in ("width", "height"))))
