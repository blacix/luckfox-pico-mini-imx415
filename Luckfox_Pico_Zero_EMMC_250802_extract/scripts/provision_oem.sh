#!/bin/sh
# provision_oem.sh -- install the IMX415 driver, IQ tuning file and rkipc profile into /oem.
#
# Idempotent, non-destructive, and it backs up every file it modifies. Safe to re-run.
# Run on the board after booting the imx415 boot image, or on a fresh board right after
# flashing it, with the four payload files sitting in /tmp:
#     imx415.ko  imx415_CMK-OT2022-PX1_IR0147-36IRC-8M-F20.json
#     rkipc-imx415-720p.ini  provision_oem.sh
#
# /oem, /userdata and / are UBIFS and already mounted rw, so this is ordinary file copying --
# no flash surgery. Only /oem/usr/bin/RkLunch.sh is edited, once, from its own backup.
set -u
SRC=${1:-/tmp}
KO=/oem/usr/ko
SHARE=/oem/usr/share
RK=/oem/usr/bin/RkLunch.sh
IQ=imx415_CMK-OT2022-PX1_IR0147-36IRC-8M-F20.json
INI=rkipc-imx415-720p.ini
say() { echo "[provision] $*"; }

# 1. driver module. insmod_ko.sh already carries "__insmod imx415.ko" ahead of
#    video_rkcif.ko/video_rkisp.ko, so placing the file is all that is needed.
if [ -f "$SRC/imx415.ko" ]; then
	cp -f "$SRC/imx415.ko" "$KO/imx415.ko" && chmod 664 "$KO/imx415.ko"
	say "installed $KO/imx415.ko"
else
	say "MISSING $SRC/imx415.ko"
fi

# 2. ISP tuning file. rkipc is started as "rkipc -a /oem/usr/share/iqfiles", and rkaiq looks the
#    file up as <driver>_<camera-module-name>_<lens-name>.json, which is exactly this name;
#    /etc/iqfiles is only a symlink here, so one copy covers both paths.
if [ -f "$SRC/$IQ" ]; then
	mkdir -p "$SHARE/iqfiles"
	cp -f "$SRC/$IQ" "$SHARE/iqfiles/$IQ" && chmod 644 "$SHARE/iqfiles/$IQ"
	say "installed $SHARE/iqfiles/$IQ"
else
	say "MISSING $SRC/$IQ"
fi

# 3. rkipc profile
if [ -f "$SRC/$INI" ]; then
	cp -f "$SRC/$INI" "$SHARE/$INI" && chmod 644 "$SHARE/$INI"
	say "installed $SHARE/$INI"
else
	say "MISSING $SRC/$INI"
fi

# 4. teach RkLunch.sh to select that profile. Its selector walks lsmod and does
#    "ln -s -f .../rkipc-<n>w.ini /tmp/rkipc-factory-config.ini" per match, with the LAST match
#    winning, and it knows sc530ai/sc4336/sc3336 only -- without an imx415 branch rkipc aborts
#    with "Error: not found rkipc.ini !!!". The imx415 block must come AFTER the sc3336 block,
#    because sc3336.ko is loaded unconditionally by insmod_ko.sh and would otherwise win.
#    The file installed here is built and "sh -n" checked on the host by scripts/patch_rklunch.py;
#    this script only ever installs it, and keeps a one-time backup of the original.
if grep -q "grep imx415" "$RK"; then
	say "RkLunch.sh already has the imx415 branch"
elif [ ! -f "$SHARE/$INI" ]; then
	say "not touching RkLunch.sh: $SHARE/$INI is absent"
elif [ ! -f "$SRC/RkLunch.sh" ] || ! grep -q "grep imx415" "$SRC/RkLunch.sh"; then
	say "no pre-patched RkLunch.sh in $SRC -- skipping (run scripts/patch_rklunch.py on the host)"
else
	[ -f "$RK.bak" ] || { cp -f "$RK" "$RK.bak"; say "backed up $RK -> $RK.bak"; }
	cp -f "$SRC/RkLunch.sh" "$RK" && chmod 755 "$RK"
	sh -n "$RK" && say "installed $RK (parses as valid sh)" \
		|| say "*** installed RkLunch.sh DOES NOT PARSE -- restore with: cp $RK.bak $RK ***"
	grep -n -B1 -A3 "grep imx415" "$RK" | sed 's/^/  /'
fi

say "verifying"
for f in "$KO/imx415.ko" "$SHARE/iqfiles/$IQ" "$SHARE/$INI"; do
	[ -f "$f" ] && printf "  %9d  %s\n" "$(wc -c < "$f")" "$f" || echo "  MISSING $f"
done
sha256sum "$KO/imx415.ko" 2>/dev/null | sed 's/^/  ko sha256 /'
sh -n "$RK" && echo "  RkLunch.sh parses as valid sh" || echo "  *** RkLunch.sh DOES NOT PARSE ***"
grep -n -A3 "grep imx415" "$RK" | sed 's/^/  /'
