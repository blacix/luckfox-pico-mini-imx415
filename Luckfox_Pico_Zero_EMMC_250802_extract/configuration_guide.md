# IMX415 Native 720p & High-Quality CBR Configuration

This guide explains how to bypass the 4K default sensor crop, force a full-field-of-view 720p readout, and configure the `rkipc` encoder for a high-quality 2 Mbps Constant Bitrate (CBR) stream without the system overwriting your settings.

## Step 1: Stop the Active Camera Pipeline
The camera daemon flushes its memory to the `.ini` file on exit, so we must forcefully kill it before making copies or edits.

```bash
killall -9 rkipc 2>/dev/null
```

## Step 2: Create a Persistent Custom Config File
To prevent the system's `RkLunch.sh` script from deleting your settings, copy the default configuration to a new file that the system won't touch.

```bash
cp /userdata/rkipc.ini /userdata/rkipc_custom.ini
```

## Step 3: Modify the Encoder Settings
Open `/userdata/rkipc_custom.ini` using a text editor (like `vi`).

```bash
vi /userdata/rkipc_custom.ini
```

Locate the `[video.0]` section and update it to exactly match the block below. This configures the encoder for 1280x720 at 25 FPS, sets a strict 2 Mbps target, and prevents the macroblocking (QP) from going above 34.

```ini
[video.0]
buffer_size = 921600 ; w * h
buffer_count = 4
enable_refer_buffer_share = 1
stream_type = mainStream
video_type = compositeStream
max_width = 1280
max_height = 720
width = 1280
height = 720
rc_mode = CBR
rc_quality = high
src_frame_rate_den = 1
src_frame_rate_num = 25
dst_frame_rate_den = 1
dst_frame_rate_num = 25
target_rate = 2048
mid_rate = 2048
max_rate = 2048
min_rate = 1800
output_data_type = H.264
smart = close
h264_profile = high
gop = 25
smartp_viridrlen = 25
gop_mode = normalP
stream_smooth = 50
enable_motion_deblur = 0
motion_deblur_strength = 0
enable_motion_static_switch = 0
frame_min_i_qp = 16
frame_min_qp = 18
frame_max_i_qp = 32
frame_max_qp = 34
scalinglist = 0
enable_debreath_effect = 0
debreath_effect_strength = 16
thrd_i = 0,0,0,0,3,3,5,5,8,8,8,15,15,20,25,25
thrd_p = 0,0,0,0,3,3,5,5,8,8,8,15,15,20,25,25
aq_step_i = -8,-7,-6,-5,-4,-3,-2,-1,0,1,2,3,4,5,7,8
aq_step_p = -8,-7,-6,-5,-4,-3,-2,-1,0,1,2,3,4,5,7,8
qbias_enable = 1
qbias_i = 171
qbias_p = 85
flt_str_i = 0
flt_str_p = 0
cu_dqp = 1
anti_ring = 2
anti_line = 2
lambds = 4
```
*(Save and exit your editor. In `vi`, press `ESC`, type `:wq`, and hit `Enter`)*.

Run `sync` to ensure the file is saved to flash.

## Step 4: Force the Sensor to Native 720p (Full FOV)
By default, the driver requests 4K and crops it. We use `media-ctl` to force the V4L2 subdevice directly into its native `1284x720` mode before the encoder starts.

```bash
media-ctl -d /dev/media0 --set-v4l2 '"m00_b_imx415 4-0037":0[fmt:SGBRG12_1X12/1284x720]'
```

## Step 5: Launch the Stream with Custom Parameters
Start `rkipc` in the background, specifically pointing it to your custom configuration file (`-c`) and the directory containing your IMX415 IQ tuning file (`-a`).

```bash
rkipc -c /userdata/rkipc_custom.ini -a /oem/usr/share/iqfiles &
```

## Step 6: Automating on Boot (Optional Wrapper)
To make this permanent on every boot without modifying the read-only `/oem` partition, create a startup wrapper script in `/userdata/`:

```bash
cat << 'EOF' > /userdata/start_camera.sh
#!/bin/sh
# Kill default processes
killall -9 rkipc 2>/dev/null
sleep 1

# Force native 720p
media-ctl -d /dev/media0 --set-v4l2 '"m00_b_imx415 4-0037":0[fmt:SGBRG12_1X12/1284x720]'

# Start with custom config
rkipc -c /userdata/rkipc_custom.ini -a /oem/usr/share/iqfiles &
EOF

chmod +x /userdata/start_camera.sh
```

You can now manually run `/userdata/start_camera.sh` after boot to cleanly switch to your high-quality full-FOV 720p stream.

---

# Verification on hardware (applied and measured 2026-10-18, board `10.15.116.182`)

Everything above is applied and running. The encoder half of this guide is correct and the effect is
large; **step 4's premise is wrong on this module** — see the measurement below, because it changes
which sensor mode you will want.

## What was placed, and where the reproducible sources live

| On the board | Repo source | Purpose |
| --- | --- | --- |
| `/userdata/rkipc_custom.ini` | `scripts/make_custom_ini.py` → `image/oem/rkipc_custom.ini` | step 2 + 3, the 2 Mbps CBR encoder block |
| `/userdata/start_camera.sh` | `scripts/start_camera.sh` | steps 1, 4, 5 as one idempotent run |
| `/userdata/S99startcamera` | `scripts/S99startcamera` | step 6, **deliberately inert** — active only if you copy it to `/etc/init.d/` |

`make_custom_ini.py` generates the ini instead of hand-editing it: it rewrites only the 49 `[video.0]`
keys the guide names, refuses if the source profile contains a key the guide does not cover, and
leaves every other section (`[isp*]` tuning, IQ path, OSD, `network.ntp`) byte-identical — verified,
all 15 other sections compare equal and `[video.0]`'s key order is preserved. 15 of its 49 keys
actually differed from the shipped profile:

```
rc_quality   normal→high    target_rate 0→2048      mid_rate 4096→2048   max_rate 8192→2048
min_rate     0→1800         h264_profile normal→high gop 30→25            src/dst_frame_rate_num 30→25
enable_motion_deblur 1→0    motion_deblur_strength 3→0
frame_min_i_qp 26→16  frame_min_qp 28→18  frame_max_i_qp 51→32  frame_max_qp 51→34
```

Why step 1 is genuinely required: `RkLunch.sh` ends with an unconditional
`cp $default_rkipc_ini $rkipc_ini -f`, so `/userdata/rkipc.ini` is overwritten from the factory
profile **every boot** — editing that file is futile, which is exactly what step 2's separate filename
is for. Note that step 2's *source* is whatever the `lsmod` selector in `RkLunch.sh` happened to pick;
`make_custom_ini.py` derives from `/oem/usr/share/rkipc-imx415-720p.ini` directly so it is
deterministic.

## Measured result

| | before (stock pipeline) | after (`start_camera.sh`) |
| --- | --- | --- |
| H.264 profile | `normal` | **High** |
| Bitrate achieved | **86 kbps** | **2.19 – 2.32 Mbps** (target 2048, +7…13 % CBR overshoot) |
| Delivered frames | 1280x720 @ ~20 fps | 1280x720 @ **27.5 fps** |
| IDR spacing | 30 frames | **25 frames exactly** (frames 0, 25, 50, 75 … — `gop = 25` confirmed) |
| ISP work per frame | scale from `Dcrop(0,0\|3072x1728)`, 37 ms | `Dcrop(0,0\|1280x720)` passthrough, **6 ms** |
| Frame errors | `frameloss:0`, `all err count:0` | same, over 34 219 frames |
| Picture sanity | `YAVG 102`, neutral chroma | `YAVG 96.6`, `UAVG 128.1`, `VAVG 128.4` — real scene, 3A converging |

The old profile was `rc_mode = CBR` in name only: `target_rate = 0`, `min_rate = 0` and
`frame_max_qp = 51` let the rate controller fall to 86 kbps and run the quantiser to 51. Independent
confirmation that the QP cap earns its place: high-frequency energy of a decoded frame (centre
640×360, Laplacian variance) went **1528 → 4595**, about 3× the fine detail surviving. Objective but
indicative — the two captures are 11 minutes apart, so small scene changes are included.

## Correction 1: step 4 narrows the field of view on this module

`1284x720` is not "the full sensor readout at 720p"; it is a **centre window** of the array, while the
8 MP mode `3864x2192` that the ISP crops to `3072x1728` covers nearly all 3840 columns. Photographed
of the same scene seconds apart with identical encoder settings
(`image/log/fov_left-8mp-crop_vs_right-native-1284x720.png`, left = 8 MP + crop, right = native
`1284x720`): the chair back, the white panel and the shelf are all clearly **magnified on the right**,
and the left frame keeps scene at its edges — the water cooler, the window, the desk with the cloth —
that the right frame has lost. Going back to `3864x2192` reproduces the wide framing to a mean pixel
difference of 2.87 (0.04 % of pixels differ by more than 60, all of them the burned-in clock), so this
is repeatable and not a one-off.

`media-ctl` could not have answered this: `crop.bounds` comes back in each readout's **own**
coordinates (`(0,0)/1284x720` vs `(12,16)/3840x2160`), never as a position on the physical array. Only
framing the two and registering them can. Three earlier attempts at that measurement were invalid and
are listed so nobody repeats them: an 80×19-pixel correlation scored high at *every* scale (a scene
with little high-frequency content cannot discriminate, and a metric whose candidates all score high
is measuring nothing); and two versions indexed a gradient field with the wrong stride — a gradient
array is one sample narrower than its grid, so the correlation was reading across rows.

So `start_camera.sh` carries a `MODE` switch: the two modes are a genuine trade and the encoder
settings are identical either way.

```sh
/userdata/start_camera.sh                # native 1284x720: 27.5 fps, ~1.2-1.6x zoom, least FOV
MODE=8mp /userdata/start_camera.sh       # 3864x2192 + ISP crop: widest FOV, ~20 fps
```

It sets the subdev format in both directions, so `MODE=8mp` also undoes a previous selection without
a reboot. The default stays `native` — what this guide asks for, and the right choice for a fixed
camera you frame once; pick `8mp` if you need the corners of the room.

## Correction 2: step 5 does not work as written from a non-login shell

`rkipc` lives in `/oem/usr/bin` and `librockit.so` in `/oem/usr/lib`; both directories enter `PATH` /
`LD_LIBRARY_PATH` only via `/etc/profile.d/RkEnv.sh`, which a login shell sources and
`ssh root@board /userdata/start_camera.sh` does not — the guide's line then dies with
`rkipc: not found`. `start_camera.sh` therefore opens with the same line `/etc/init.d/S21appinit`
opens with:

```sh
[ -f /etc/profile.d/RkEnv.sh ] && . /etc/profile.d/RkEnv.sh
```

## Three smaller notes from running it

* **After a reboot the ini's bytes change and its settings do not.** rkipc rewrites its ini on exit,
  so `rkipc_custom.ini` came back re-formatted (aligned `=`, the `; w * h` comment dropped, md5
  `e0f37e8a…` → `e14e3cfd…`). All 15 changed values survived verbatim. A changed hash here is not
  lost settings; re-run `make_custom_ini.py` if you want the original layout back.
* **Delivered rate overshoots the requested 25 fps** (27.5 fps seen): the mode's timing ceiling is
  ~27.7 fps and the encoder does not drop frames to hit 25, so `gop = 25` is an IDR every 25 *frames*
  = every 0.91 s, not every second. Harmless; use `gop = 28` for a 1-second GOP at the delivered rate.
* **8 MP mode runs at ~20 fps, not the 15 fps its format string claims** (`3864x2192@10000/150000`,
  yet `rate:48ms` in `/proc/rkisp-vir0`; measured 248 CIF frames in 12 s). The mode string is nominal
  — do not size a recording around 15 fps.
* **A reboot silently discards this whole configuration, and the stream is refused while the board is
  coming up.** Confirmed by catching one in the act: after a reboot `pidof rkipc` returned pid 303
  with cmdline `rkipc -a /oem/usr/share/iqfiles` — no `-c`, so the factory profile — serving
  `Dcrop(0,0|3072x1728)` and delivering a measured **37 kbps at 19 fps**, i.e. the picture quality this
  guide exists to fix. rkipc itself starts only ~2 s after boot, but the eth0 address takes longer to
  appear, so for the first tens of seconds of a boot a player gets a connection refused and reports
  `VLC is unable to open the MRL` on a *correct* URL. So: if a URL that used to work suddenly will not
  open, check `uptime -s` / `cut -d. -f1 /proc/uptime` on the board before anything else, then re-run
  `/userdata/start_camera.sh`. To stop the revert recurring, install the step-6 hook
  (`/etc/init.d/S99startcamera` — rootfs is writable; verified with a create-and-delete test).

## Reverting

Nothing outside `/userdata` was touched — neither `/oem` nor the `boot` partition — so a plain
`reboot` returns the board to the stock pipeline, since stock `RkLunch.sh` starts
`rkipc -a /oem/usr/share/iqfiles` on the factory profile. If you installed the step-6 hook, remove it
first: `rm /etc/init.d/S99startcamera`.

## Watching it from a workstation (VLC), and what each failure means

The player URL is **`rtsp://<board>:554/live/0`** — the path matters, and this server answers
differently per path (measured with a raw `DESCRIBE`, and reproduced inside VLC 3.0.23):

| Path | Server says | What the player does |
| --- | --- | --- |
| `/live/0` | `RTSP/1.0 200 OK` | **the one to use** — decodes over TCP *and* UDP: `Received first picture`, VideoToolbox decoding h264, `g711` audio at 8 kHz |
| `/live/1` | `RTSP/1.0 200 OK` | **advertised but silent**: the session opens and never delivers one byte, so VLC shows a black window forever |
| `/video/0` | `RTSP/1.0 454 Session Not Found` | `VLC is unable to open the MRL 'rtsp://…/video/0'` — this is **not** a path on this firmware, despite being common on other Rockchip builds |
| `/stream0` | `RTSP/1.0 454 Session Not Found` | `VLC is unable to open the MRL 'rtsp://…/stream0'` |
| `/` | `RTSP/1.0 454 Session Not Found` | same |

`/live/1` is the nastiest of the five, because it fails without an error: everything looks healthy,
which is exactly what "rkipc appears to be running but I can't access the stream" tends to be.

And when VLC prints `VLC is unable to open the MRL`, check the **host** before the settings — a URL
that differs from the board's address by one digit fails the same way a bad path does. `rtsp://…/live/0`
pointed at an address that is not the board gives `Connection refused` on every path, which is exactly
what was observed for `10.15.116.18` (nonexistent, 100 % packet loss) versus the board's
`10.15.116.182`.

Two player notes:

* **VLC's default RTSP transport is UDP.** It works on this network, but if a firewall or a
  client-isolating network drops the RTP port, VLC hangs. Force TCP: *Tools → Preferences → Input
  / Codecs → Live555 stream connection → TCP*, or `vlc --rtsp-tcp 'rtsp://<board>:554/live/0'`.
* **Tools → Messages at verbosity 2 prints the RTSP reply VLC actually received**, which names the
  cause outright: `454 Session Not Found` is the path, `connection error` is the route.

**The server is not single-client, and a stuck player does not need an rkipc restart.** Verified: six
concurrent clients were all served media at once, and a fresh client was served normally 2 s after all
six had been `SIGKILL`ed — so no session-slot starvation and no lingering ghost sessions. If a path
returns media on one machine and not another, look at the route between them, not at rkipc.

`scripts/watch_stream.sh` runs all of this from the workstation in one go (no board-side install):
route check, the per-path `DESCRIBE` table, and the delivered bitrate/frame rate. Typical healthy
output on this build is `~1.25-2.0 Mbps, ~25-27 fps`.

### If it worked and then stopped: rkipc must be detached from its launcher

A third cause sits behind the same symptom, and it was a real defect in `start_camera.sh`. Launching
rkipc as `rkipc … &` backgrounds it but leaves it in the caller's session, so starting it with
`ssh root@board /userdata/start_camera.sh` kills it as soon as that ssh command returns and the pty
is destroyed — SIGHUP reaches the session and rkipc releases the encoder. The board looked fine
because `ps` output was remembered, while `pidof rkipc` was empty, the `0.0.0.0:554` listener was gone,
and `dmesg` read `venc_release` / `vrgn_release` / `vsys_release` / `s_power 0` with **uptime still
climbing** (no reboot). The fix, now in the script:

```sh
nohup setsid "$RKIPC" -c "$INI" -a "$IQ" > /tmp/rkipc.log 2>&1 < /dev/null &
```

`nohup` installs `SIG_IGN` for SIGHUP, `setsid` moves rkipc into its own session, and stdin from
`/dev/null` stops it blocking on a pty that no longer exists. Verified: rkipc came back as
`ppid=1 pgrp=3133 sid=3133` — a session leader adopted by init — and kept streaming after the ssh
session that started it had closed. So the first two things to check when a stream is refused are
`pidof rkipc` and the listener, both cheap and both on the board:

```sh
pidof rkipc;                     awk '$4=="0A" && $2 ~ /:022A/' /proc/net/tcp   # 022A = port 554
```


Two pitfalls worth recording, both of which produced a *false* "the board is broken" reading during
this investigation:

* `ffmpeg -t N -f null -` **does not reliably terminate** against this server — it can sit ESTABLISHED
  and idle indefinitely. `-t N -c copy -f h264 <file>` always returns, so every probe in
  `watch_stream.sh` writes a real file. A byte-count-only check also cannot tell `/live/0` from
  `/live/1`, since one is refused and the other is accepted-and-silent; hence the direct `DESCRIBE`.
* macOS has no `timeout` binary, so bounds must be explicit background-and-kill.