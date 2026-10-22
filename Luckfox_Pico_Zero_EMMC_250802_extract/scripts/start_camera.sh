#!/bin/sh
# start_camera.sh -- run the IMX415 in its native 1284x720 window and encode it as
# high-quality 2 Mbps CBR 720p, without touching the read-only-by-convention /oem tree.
#
# Lives in /userdata (writable UBIFS) and is not referenced by RkLunch.sh, so nothing
# overwrites it. Run it after boot, any time:
#       /userdata/start_camera.sh
#
# Why each step is needed:
#  * kill rkipc first: it holds /dev/media0, /dev/video* and the VENC channels, and it
#    flushes its in-memory settings to its ini on exit, so a graceful stop would undo an
#    edited ini. It must be gone before media-ctl can re-time the sensor subdev.
#  * media-ctl selects which of the driver's two 2-lane readouts to use, and the choice is a
#    trade, not a free win -- see MODE below, and configuration_guide.md's verification section
#    for the photographs that established it.
#  * -c points rkipc at rkipc_custom.ini. Left to itself rkipc reads /userdata/rkipc.ini,
#    which RkLunch.sh overwrites with the factory profile on every boot.
#  * -a is the IQ directory; without it rkaiq has no tuning for imx415 and the picture is
#    un-white-balanced and un-demosaiced.

INI=/userdata/rkipc_custom.ini
IQ=/oem/usr/share/iqfiles
SEN='"m00_b_imx415 4-0037":0'

# Which sensor readout to use.  Measured on this board, not assumed:
#
#   native  media-ctl 1284x720 -> ISP passthrough Dcrop(0,0|1280x720), 6 ms/frame,
#           27.5 fps delivered.  It reads only a CENTRE WINDOW of the array, so the
#           picture is ~1.2-1.6x zoomed in: objects look bigger and the edges of the
#           scene are lost.
#   8mp     the driver default 3864x2192 -> ISP Dcrop(0,0|3072x1728), 37 ms/frame,
#           ~20 fps delivered, but that crop covers nearly the whole 3840-column array,
#           so this is the WIDE-angle framing of the two.
#
# configuration_guide.md step 4 calls the first one "full field of view"; on this module
# it is the opposite (see the side-by-side in configuration_guide.md's verification
# section).  The encoder settings are identical either way, so pick by framing:
#
#       MODE=8mp /userdata/start_camera.sh      # widest FOV, ~20 fps
#       /userdata/start_camera.sh               # guide default: 27.5 fps, narrower FOV
MODE=${MODE:-native}
case "$MODE" in
	native) FMT='SGBRG12_1X12/1284x720' ;;   # centre window, 27.5 fps, zoomed framing
	8mp)    FMT='SGBRG12_1X12/3864x2192' ;;  # near-full-array readout, ~20 fps, widest FOV
	*) echo "[start_camera] MODE must be 'native' or '8mp' (got '$MODE')"; exit 1 ;;
esac

# rkipc is in /oem/usr/bin and its rockit libraries in /oem/usr/lib, and both directories are
# only added to PATH / LD_LIBRARY_PATH by /etc/profile.d/RkEnv.sh, which a login shell
# sources and a non-login one (e.g. `ssh root@board /userdata/start_camera.sh`) does not.
# Sourcing it here is the same line /etc/init.d/S21appinit starts with; without it the
# script fails with "rkipc: not found", or worse starts rkipc without librockit.so.
[ -f /etc/profile.d/RkEnv.sh ] && . /etc/profile.d/RkEnv.sh
RKIPC=$(command -v rkipc || echo /oem/usr/bin/rkipc)

# Check the profile before taking anything down: a missing ini is a reason to change nothing,
# not a reason to leave the camera with no stream.
if [ ! -f "$INI" ]; then
	echo "[start_camera] ERROR: $INI missing -- run scripts/make_custom_ini.py and push it"
	exit 1
fi

echo "[start_camera] stopping stock pipeline"
killall -9 rkipc 2>/dev/null

# killall only sends the signal; the V4L2 nodes stay busy until the kernel has finished
# tearing down the pipeline, and media-ctl then fails with EBUSY. Wait for it instead of
# trusting a fixed sleep, but give up rather than hang forever.
i=0
while [ $i -lt 20 ]; do
	pidof rkipc >/dev/null || break
	sleep 0.5
	i=$((i + 1))
done
sleep 1

# Both directions are set explicitly, so MODE=8mp also undoes a previous native selection
# without needing a reboot.
echo "[start_camera] selecting sensor window $FMT (MODE=$MODE)"
if media-ctl -d /dev/media0 --set-v4l2 "$SEN[fmt:$FMT]"; then
	echo "[start_camera] sensor is now: $(media-ctl -d /dev/media0 --get-v4l2="$SEN" 2>&1)"
else
	echo "[start_camera] WARNING: media-ctl rejected $FMT; using whatever the driver had"
fi

echo "[start_camera] starting rkipc with $INI"
# Detach it properly -- plain backgrounding is not enough, and this is a bug that actually
# bit: run this script through ssh (`ssh root@board /userdata/start_camera.sh`) and the pty
# is destroyed the moment the command returns, after which SIGHUP reaches the session and
# kills rkipc.  Observed on this board: rkipc died ~100 s after such a session ended, with
# no reboot (dmesg: venc_release / vsys_release / s_power 0), the 0.0.0.0:554 listener gone
# and VLC reporting "unable to open the MRL" while rkipc "looked like it was running".
# nohup installs SIG_IGN for SIGHUP and setsid moves rkipc out of the session outright, so
# the stream now outlives whatever terminal started it; stdin comes from /dev/null so it can
# never block on a pty that no longer exists.
LOG=/tmp/rkipc.log
if command -v setsid >/dev/null 2>&1; then
	nohup setsid "$RKIPC" -c "$INI" -a "$IQ" > "$LOG" 2>&1 < /dev/null &
else
	nohup "$RKIPC" -c "$INI" -a "$IQ" > "$LOG" 2>&1 < /dev/null &
fi
echo "[start_camera] launched, detached; rkipc log: $LOG"
echo "[start_camera] wait ~8 s for 3A + RTSP, then open rtsp://<board>:554/live/0"
