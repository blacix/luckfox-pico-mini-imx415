#!/usr/bin/env python3
"""Derive /userdata/rkipc_custom.ini from the IMX415 720p factory profile.

configuration_guide.md step 3 asks for a [video.0] block tuned for a high-quality
2 Mbps CBR stream at 25 fps. This does that by rewriting only the *values* of the keys
the guide names, so every other byte of the profile -- the whole [isp*] tuning block, IQ
handling, osd, network.ntp, the comment "; w * h" -- survives untouched, and the section
keeps its original key order (rkipc rewrites this file itself on exit, so a stable layout
matters: whatever we write is what rkipc will re-emit later).

Why a separate file instead of editing /userdata/rkipc.ini: RkLunch.sh ends with an
unconditional `cp $default_rkipc_ini $rkipc_ini -f`, so /userdata/rkipc.ini is replaced by
the factory profile on every boot. Anything kept there is lost at the next reboot; the
system has no rule for rkipc_custom.ini, so it persists.

Why these values: the shipped profile has rc_mode = CBR but target_rate = 0,
min_rate = 0 and frame_max_qp = 51, which in the hardware rate controller means "CBR in
name only" -- measured 86 kbps at 18 fps on this board, with the quantiser allowed to run
to 51 (visible macroblocking). Pinning target/mid/max to 2048 with a 1800 floor holds the
bitrate, and capping QP at 32/34 (I/P) bounds the worst-case macroblocking even on a
high-motion scene. 25 fps because the sensor's native 1284x720 window runs at 25 fps on
two MIPI lanes, so encoder and sensor then agree instead of fighting over timestamps.
"""
import re
import sys

src, dst = sys.argv[1], sys.argv[2]
text = open(src).read()

# The [video.0] block from configuration_guide.md step 3, as key -> wanted value.
TARGET = [
    ("buffer_size", "921600"),          # 1280 * 720
    ("buffer_count", "4"),
    ("enable_refer_buffer_share", "1"),
    ("stream_type", "mainStream"),
    ("video_type", "compositeStream"),
    ("max_width", "1280"),
    ("max_height", "720"),
    ("width", "1280"),
    ("height", "720"),
    ("rc_mode", "CBR"),
    ("rc_quality", "high"),
    ("src_frame_rate_den", "1"),
    ("src_frame_rate_num", "25"),
    ("dst_frame_rate_den", "1"),
    ("dst_frame_rate_num", "25"),
    ("target_rate", "2048"),
    ("mid_rate", "2048"),
    ("max_rate", "2048"),
    ("min_rate", "1800"),
    ("output_data_type", "H.264"),
    ("smart", "close"),
    ("h264_profile", "high"),
    ("gop", "25"),
    ("smartp_viridrlen", "25"),
    ("gop_mode", "normalP"),
    ("stream_smooth", "50"),
    ("enable_motion_deblur", "0"),
    ("motion_deblur_strength", "0"),
    ("enable_motion_static_switch", "0"),
    ("frame_min_i_qp", "16"),
    ("frame_min_qp", "18"),
    ("frame_max_i_qp", "32"),
    ("frame_max_qp", "34"),
    ("scalinglist", "0"),
    ("enable_debreath_effect", "0"),
    ("debreath_effect_strength", "16"),
    ("thrd_i", "0,0,0,0,3,3,5,5,8,8,8,15,15,20,25,25"),
    ("thrd_p", "0,0,0,0,3,3,5,5,8,8,8,15,15,20,25,25"),
    ("aq_step_i", "-8,-7,-6,-5,-4,-3,-2,-1,0,1,2,3,4,5,7,8"),
    ("aq_step_p", "-8,-7,-6,-5,-4,-3,-2,-1,0,1,2,3,4,5,7,8"),
    ("qbias_enable", "1"),
    ("qbias_i", "171"),
    ("qbias_p", "85"),
    ("flt_str_i", "0"),
    ("flt_str_p", "0"),
    ("cu_dqp", "1"),
    ("anti_ring", "2"),
    ("anti_line", "2"),
    ("lambds", "4"),
]

m = re.search(r"(?ms)^(\[video\.0\]\n)(.*?)(?=^\[|\Z)", text)
if not m:
    sys.exit("no [video.0] section in " + src)
head, body = m.group(1), m.group(2)

have = dict(re.findall(r"(?m)^([A-Za-z0-9_]+)\s*=\s*([^;]*?)\s*(?:;.*)?$", body))
# Refuse rather than guess: a missing key would mean this is not the profile the guide was
# written against, and silently adding keys rkipc does not expect is worse than stopping.
missing = [k for k, _ in TARGET if k not in have]
if missing:
    sys.exit("source [video.0] is missing %s -> not the expected profile" % ", ".join(missing))
extra = [k for k in have if k not in dict(TARGET)]
if extra:
    sys.exit("source [video.0] has keys the guide does not cover: %s" % ", ".join(sorted(extra)))

changed = []
for key, want in TARGET:
    if have[key] != want:
        # Anchored to the start of the line and to the first "=" so the "; w * h" comment
        # and any trailing whitespace stay where they are.
        new, n = re.subn(r"(?m)^%s = \S+" % re.escape(key), "%s = %s" % (key, want), body, count=1)
        if n != 1:
            sys.exit("could not rewrite %s" % key)
        body = new
        changed.append((key, have[key], want))

out = text[:m.start()] + head + body + text[m.end():]
open(dst, "w").write(out)

print("changed %d of %d keys in [video.0]:" % (len(changed), len(TARGET)))
for key, old, want in changed:
    print("  %-28s %-10s -> %s" % (key, old, want))
print("\nwrote %s  (%d bytes, %d bytes source)" % (dst, len(out), len(text)))
