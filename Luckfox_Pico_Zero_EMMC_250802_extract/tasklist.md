# IMX415 File Acquisition — Tasklist

**Scope of this document:** obtain the three artifacts listed in `files_to_get.md` from the
Luckfox Pico Zero firmware, verify they are usable on our custom RV1103 board, and stage them
for deployment. **Execution of `camera_bringup.md` (actual bring-up) is a separate, later step.**

Source images: `camera/Luckfox_Pico_Zero_EMMC_250802/` (`oem.img`, `rootfs.img`, `boot.img`,
`userdata.img` — the first three are **ext4**; `boot.img` is a Rockchip boot/DTB container).
Target board: `root@10.15.116.182` (pw `luckfox`), Luckfox Pico Plus firmware, RV1103,
kernel `5.10.160` armv7l, Buildroot 2023.02.6, UBIFS rootfs + `/oem` + `/userdata` (all `rw`).

---

## Artifacts to obtain (from `files_to_get.md`)

| # | Artifact | Lands on target | Source in Pico Zero image |
|---|---|---|---|
| A | `imx415_*.json` ISP tuning (IQ) file | `/etc/iqfiles/` (+ `/oem/usr/share/iqfiles/`) | `/oem/usr/share/iqfiles/` in `oem.img`; fallback `/etc/iqfiles/` in `rootfs.img` |
| B | `imx415.ko` kernel driver | `/oem/usr/ko/` | `/oem/usr/ko/imx415.ko` in `oem.img` |
| C | 2-lane DT config (`data-lanes = <1 2>;`) | our board's DTB / overlay | sensor + `csi_dphy` endpoint nodes in `boot.img` DTB (4-lane reference) |

## Staging layout to create

```
camera/extracted/imx415/
├── iqfiles/     # imx415_*.json
├── ko/          # imx415.ko (+ depends, insmod_ko.sh, release_version.txt)
├── dtb/         # carved DTBs, decompiled .dts, captured endpoint nodes
├── _work/       # scratch: hashes, carving helpers, live DT dump
└── MANIFEST.md  # sha256, sizes, vermagic, provenance of every extracted file
```

## Ground rules

- **Read-only against the source images.** Never mount them read-write, never write to them;
  extract with `debugfs`/`e2cp` so images stay byte-identical (re-verify sha256 at the end).
- **No writes to the target board in Phases 0–6.** Phase 7 (deploy) is the first device write and
  is gated on your go-ahead.
- Nothing is deleted; anything pulled off the device is stored under `_work/`.

---

## Phase 0 — Host tooling (macOS on Apple Silicon, brew prefix `/usr/local`)

- [x] **0.1** Install ext4 + DTB readers — all plain CLI, **no macFUSE / no kernel extension**
      (deliberately avoiding `ext4fuse`, which would need a DriverKit extension plus
      System Settings approval on an M5 Mac):
      `brew install e2tools e2fsprogs dtc`
      → `e2ls`, `e2cp` (in `/usr/local/bin`), `debugfs` (keg-only:
      `/usr/local/opt/e2fsprogs/sbin/debugfs`), `dtc`/`fdtdump`.
- [x] **0.2** Record `shasum -a 256` of all source images into `_work/source_hashes.txt`
      (baseline that proves the images were never modified).
- [x] **0.3** Create the staging layout shown above.
- [x] **0.4** *(fallback only if brew fails)* (a) start Docker Desktop and read the images from a
      throwaway `alpine` container with `e2fsprogs`; (b) `brew install sevenzip` and test
      `7z l oem.img` — 7-Zip ext4 read support is **unverified**, test before relying on it.

## Phase 1 — Inventory the source filesystems (listing only)

- [x] **1.1** Confirm the exact module name/size:
      `debugfs -R "ls -l /oem/usr/ko" oem.img | grep -iE "imx415|insmod|release_version"`
- [x] **1.2** Locate every IMX415 IQ JSON, in both candidate roots plus a full-tree sweep:
      `debugfs -R "ls -l /oem/usr/share/iqfiles" oem.img`,
      `debugfs -R "ls -l /etc/iqfiles" rootfs.img`, then a recursive `ls -l` sweep for
      `*imx415*` across `oem.img` + `rootfs.img` (also `/oem/usr/etc`, `/oem/usr/bin`, `/userdata`).
- [x] **1.3** Dump the source `insmod_ko.sh` + `release_version.txt` — these date the Pico Zero SDK
      build and therefore tell us which kernel `imx415.ko` was compiled against.
- [x] **1.4** **Decision point:** if `imx415.ko` or the IQ JSON are missing from `oem.img`, fall back
      to `rootfs.img`/`userdata.img`; if still missing, stop and propose fetching from the Luckfox
      SDK (`external/camera_engine_rkaiq/iqfiles/isp3x/` for the IQ file, building
      `kernel/drivers/media/i2c/imx415.c` for the module) rather than guessing.
- [x] **1.5** List the full module set to carry: `imx415.ko` plus anything it needs that our target
      lacks (`video_rkcif.ko`, `video_rkisp.ko`, `phy-rockchip-csi2-dphy*.ko`, `videobuf2-*`,
      `rk_dvbm.ko`) — input for the Phase 5 comparison.

## Phase 2 — Extract artifact A (IQ JSON)

- [x] **2.1** Dump the IMX415 JSON(s) into `extracted/imx415/iqfiles/` with
      `debugfs -R "dump <src> <dest>" oem.img`.
- [x] **2.2** Validate each JSON: must parse, and check the fields rkaiq matches on —
      `sensor` / `module_name`, `isp` revision, `chip_id`, `lwol`/`CLM` — confirming it declares
      the ISP32 / RV1106-class ISP (our RV1103 shares ISP3.2 per `files_to_get.md`).
- [x] **2.3** Confirm the filename prefix equals the sensor name the driver registers (`imx415`),
      since rkaiq selects the IQ file by sensor name; record the exact path to use for
      `iq_file_dir` in Phase 7.
- [x] **2.4** If several `imx415_*.json` variants exist (e.g. `imx415_CMK-OT2119-PC1_30IRC-F16.json`),
      tabulate them with the resolution/fps modes each declares, mark which suit **2-lane +
      1080p binned**, recommend one, and ask you to confirm the physical module before committing.

## Phase 3 — Extract artifact B (`imx415.ko`)

- [x] **3.1** Dump the module set from 1.5 into `extracted/imx415/ko/`
      (`debugfs -R "rdump /oem/usr/ko <dest>" oem.img`, then keep only the needed files).
- [x] **3.2** ELF sanity check: `file imx415.ko` must report **ELF 32-bit ARM** relocatable
      (AArch64 would mean the source image is not the right family).
- [x] **3.3** Read `.modinfo`:
      `strings -a imx415.ko | grep -E '^(vermagic|name|depends|srcversion|description)='`.
- [x] **3.4** Keep the Pico Zero `insmod_ko.sh` beside it for diffing against the target's copy
      (the target's copy already calls `__insmod imx415.ko` in the right position, so the
      persistence half of `camera_bringup.md` Stage 2.4 is already satisfied).

## Phase 4 — Extract artifact C (device tree / lane config)

- [x] **4.1** Carve the DTBs out of `boot.img`: scan for `d0 0d fe ed` on 4-byte alignment, read the
      totalsize field, `dd` each blob to `dtb/picozero_N.dtb` using a small dependency-free Python
      helper kept in `_work/`, then `dtc -I dtb -O dts` each one.
- [x] **4.2** Capture the sensor node (`imx415`, `reg = <0x1a>`) under its `i2c@...` parent and its
      `port/endpoint`: `data-lanes`, `link-frequencies`, `clock-frequency`, `clock-lanes`,
      `remote-endpoint`, `reset-gpios`/`pwdn-gpios`, regulator supplies, and the linked
      `csi_dphy` / `rkcif` / `rkisp` / `pinctrl` camera-pin nodes.
- [x] **4.3** Pull the **live** DT of our own board read-only (`cat /sys/firmware/fdt` →
      `_work/target_fdt.dtb`, fallback: rebuild from `/proc/device-tree`), decompile it and diff the
      sensor + `mipi0` endpoint nodes against 4.2. This yields the exact property list our DT must
      gain or change.
- [x] **4.4** Produce the **2-lane variant**: `data-lanes = <1 2>;` (RV1103 D-PHY is 2-lane) with the
      matching `link-frequency`, and verify the extracted `imx415.ko` really reprograms the sensor
      for 2 lanes rather than hardcoding 4-lane register settings — if it hardcodes them, flag it,
      because a DT-only edit would then be insufficient.
- [x] **4.5** Determine, **without applying**, how a DT change reaches our board. Note our rootfs is
      **UBIFS**, not the ext4 of the Pico Zero EMMC image, so check: whether a `dtc`-recompiled DTB
      can be written into the `boot`/`resource` partition we boot, whether
      `/sys/kernel/config/device-tree/overlays/` (configfs) exists for a runtime overlay, and what
      `env.img`/bootargs control. Highest-uncertainty of the three artifacts — will likely need your
      input on which partition/image our board boots from.

## Phase 5 — Compatibility verification (offline, no device writes)

- [x] **5.1** **vermagic comparison** — the make-or-break test for artifact B. Compare the extracted
      `imx415.ko` vermagic against the target's own working sensor module
      (`/oem/usr/ko/mis5001.ko`) and against `uname -r` = `5.10.160`. Must match kernel version +
      `SMP`/`preempt`/`ARMv7`/`mod_unload` flags exactly.
- [x] **5.2** **modversion (CRC) check** — decide whether the target kernel uses
      `CONFIG_MODVERSIONS` (no `/proc/config.gz` on the target, so read it from the ELF: look for a
      `__versions` section in the target's own `.ko` files with a small Python ELF section-header
      reader). If CRC versioning is on, compare the undefined symbols of the extracted `imx415.ko`
      against the target's `/proc/kallsyms` CRCs and report any that disagree.
- [x] **5.3** **Cross-SoC check** — the source image is a **Pico Zero (RV1106)** build while our board
      runs **Pico Plus (RV1103)** firmware. Confirm the pipeline modules the driver binds to
      (`video_rkcif`, `video_rkisp`, `phy-rockchip-csi2-dphy*`) exist on both sides, and note the
      RV1106 `.ko` can still be unusable if the two kernels were configured differently.
- [x] **5.4** Verdict in `MANIFEST.md`, in exactly one of three buckets: (a) drop-in `.ko` OK;
      (b) `.ko` needs a rebuild from the Luckfox SDK; (c) IQ file OK / needs a different module
      profile. State the evidence, not just the conclusion.
- [x] **5.5** If bucket (b): check whether we have the Luckfox SDK + armv7 buildroot toolchain
      locally (I did **not** find an SDK in this workspace) and report what compiling `imx415.c`
      would take — do **not** start a toolchain install without your approval.

## Phase 6 — Package, manifest, hand-off

- [x] **6.1** Write `extracted/imx415/MANIFEST.md`: per file — source image, absolute path inside the
      image, size, sha256, vermagic / JSON-header summary, intended target path.
- [x] **6.2** Re-verify the source images' sha256 against `_work/source_hashes.txt` to prove the
      extraction was read-only.
- [x] **6.3** Confirm the transfer route: the board answers SSH (verified) but `sshpass` is not
      installed on the host, so either install `sshpass` or keep an `expect` wrapper under
      `camera/scripts/`; test that `scp`/`sftp` exist on the target, else pipe with
      `cat > /tmp/<file>`.
- [x] **6.4** Report to you and **stop** — deployment is Phase 7 and waits for your instruction.

## Phase 7 — Deploy + bring-up (complete — see field report and Phase 8)

- [x] **7.1** Stage files to `/tmp` first and checksum-verify on-device (`sha256sum`). — done, all four
      files re-hash identical on the target (`imx415.ko`, `imx415-2lane.dtbo`, IQ JSON, `rkipc` ini).
- [x] **7.2** `insmod imx415.ko` and read `dmesg` for probe / vermagic /
      `disagrees about version of symbol` errors **before** anything is made persistent. — done:
      `insmod` **exit 0**, module resident, **zero** dmesg errors. No probe, as predicted (no DT node).
- [x] **7.3** Persist the payload into `/oem` — done by `scripts/provision_oem.sh`, verified on device:
      `/oem/usr/ko/imx415.ko` (sha256 `3a44c6ed…`, identical to the extracted module),
      `/oem/usr/share/iqfiles/imx415_CMK-OT2022-PX1_IR0147-36IRC-8M-F20.json` (451241 B, `644`) and
      `/oem/usr/share/rkipc-imx415-720p.ini`. `/etc/iqfiles` is only a symlink to
      `/oem/usr/share/iqfiles`, so one copy covers both, and `RkLunch.sh` already passes
      `-a /oem/usr/share/iqfiles`. `/oem/usr/ko/insmod_ko.sh` line 49 **already** carried
      `__insmod imx415.ko` ahead of `video_rkcif.ko`/`video_rkisp.ko`, so no script edit was needed.
- [x] **7.3b** `RkLunch.sh` ini selector: it walks `lsmod` and last match wins, knew only
      sc530ai/sc4336/sc3336, and aborted with `Error: not found rkipc.ini !!!` for imx415. Added an
      `imx415` branch as a sibling after the sc3336 block (`scripts/patch_rklunch.py`, `sh -n`
      checked on the host before install); the original is at `RkLunch.sh.bak` and hashes identical
      to the pristine copy taken beforehand (`8d4ad13c…`).
- [x] **7.4** Ran `camera_bringup.md` Stages 3→5 after the flash — all three pass. Stage 3:
      `media-ctl -p -d /dev/media0` shows `m00_b_imx415 4-0037 → rockchip-csi2-dphy0 →
      rockchip-mipi-csi2 → stream_cif_mipi_id0 [ENABLED]`, `media1` is `rkisp0 → rkisp_mainpath`.
      Stage 4: `rkipc -a /oem/usr/share/iqfiles` starts by itself at boot (PID 304) and `/proc/
      rkisp-vir0` reports `state:working`, `ErrCnt:0`, `frameloss:0`. Stage 5: RTSP serves
      `1280x720` h264 — note the URL is **`/live/0`**, not the `/stream0` the note guesses.

## Phase 8 — Proper flashable image (you asked for an image, not in-place patching)

In-place patching of the boot partition was ruled out, and with good reason: the DTB region ends
452 bytes before the kernel and the FIT leaves only **204 bytes** of headroom, so Luckfox's own
static-overlay script would have printed `Kernel will be affected !` and then `dd`ed over the
kernel image. Instead the image was rebuilt offline from a verified dump.

- [x] **8.1** Pulled the whole 4 MiB `boot` partition read-only; sha256 verified against the board's
      own `sha256sum /dev/mtdblock3` (`ca17f335…`). Kept as `image/boot-original-backup.img`.
- [x] **8.2** Checked whether the RSA signature matters before rebuilding anything: the FIT has
      `signature { algo="sha256,rsa2048"; padding="pss"; key-name-hint="dev";
      sign-images="fdt","kernel","multi" }`, but U-Boot carries only the algorithm *name* strings
      and none of the RSA/verification code paths, the board's own vendor tooling rewrites this
      same fdt size+hash, and all three on-flash hashes verified consistent. Rebuild is therefore
      sound, and rollback exists either way.
- [x] **8.3** `scripts/build_boot_img.py`: decompiles the DTB, drops `sc4336@30`/`sc530ai@30` and
      their orphan D-PHY endpoints, adds `imx415@37` + `endpoint@3` with `data-lanes = <1 2>`,
      recompiles, refuses to emit anything if the DTB overruns the budget, regenerates the FIT
      header with the new `data-size` and recomputed sha256, and re-verifies its own output.
      Guarded by a dtc round-trip equality test on the header before it will write anything.
- [x] **8.4** Result: DTB 36148 → **35704** bytes (648 B of headroom recovered, no kernel
      relocation). `image/boot-imx415.img` differs from the original in **22146 of 4194304 bytes**
      and is byte-identical from the kernel onward; all three FIT hashes recompute to MATCH; the
      D-PHY cross-link is symmetric (`0x70 ↔ 0x71`), phandles do not collide, and there are
      **zero** dangling references.
- [x] **8.5** 720p profile from the Pico Zero tuning: `scripts/make_720p_ini.py` keeps every
      `[isp*]` tuning key untouched and changes geometry only — `[video.0]` 1280x720,
      `buffer_size` 921600, frame rates 20→30, `gop` 50→30, and `[video.jpeg]` down to 1280x720
      because `enable_jpeg = 1` must not exceed the source. It refuses to edit unless each pattern
      matches exactly once.
- [x] **8.6** `image/FLASH.md`: partition table with flash-sector offsets derived from the board's
      `mtdparts`, the flash procedure, rollback, and how to repack a true `update.img` on Linux
      (macOS has no `afptool`/`rkImageMaker`/`mkfs.ubifs`/`ubinize`).
- [x] **8.7** **Flashed and verified on hardware (2026-10-18).** `rkdeveloptool wl 0x800` failed with
      `Write LBA failed!` — bulk LBA I/O over SPI-NAND through the BootROM agent is unreliable from
      this host (its `rl` read also died at 75%), and on NAND a blind `wl` was never sound: the
      vendor's own `sd_update.txt` issues `mtd erase` before every `mtd write`. Wrote it from the
      board's Linux instead — `adb push` + `flashcp -v /dev/mtd3`, which unlocks, erases, writes
      with the kernel's real ECC and verifies. Confirmed three ways: flashcp's own verify at 100 %,
      `sha256sum /dev/mtdblock3` = `9cda2058…` equal to the image, and the BootROM loader's partial
      read matching the Linux dump byte-for-byte over 3 211 264 B. Full results in `FLASH.md`.
      A pristine copy is also stored on the board at `/oem/usr/firmware/`.
      Both hardware questions are answered: **xvclk is right** (no clock-failure string fires and
      the sensor streams), and **rkaiq runs the 8MP mode** `3864x2192` 12-bit → CIF crop
      `3072x1728` → `1280x720` out, not the native `1284x720` mode — which caps delivery at
      ~20.7 fps against the 30 fps the ini asks for.

### Corrections this phase forced on my own earlier notes

* **Partition table**: `userdata` is `0x2300000` and `rootfs` `0x2900000`, not `0x2400000` /
  `0x2A00000` as first written (the sector columns were always correct). Fixed in `FLASH.md` and
  cross-checked against `/proc/mtd`, the vendor `sd_update.txt` and `rkdeveloptool rfi`.
* **`rkdeveloptool` needs `db <loader>` after `ld`** — every command past `ld` requires loader
  mode, which the first version of the procedure omitted.
* **RTSP path** is `/live/0`, so a working stream still answers `454 Session Not Found` on
  `/stream0`; do not read that as a camera failure.
* **`write reg array error` is benign** — it fires once at stream-on into the driver's own
  `write reg array, sleep %dms` retry; the fatal `start stream failed while write regs` never
  appears and 17 563 frames followed with `all err count:0`.

---

## Phase 9 — Encoder quality + sensor-mode configuration from `configuration_guide.md` (complete, 2026-10-18)

Applied the guide's six steps over ssh, measured every claim, and corrected two of them. Board
`10.15.116.182`, nothing outside `/userdata` touched.

- [x] **9.1** Generated the custom profile with `scripts/make_custom_ini.py` (new) rather than hand-
      editing: rewrites only the 49 `[video.0]` keys the guide names, refuses on any key it does not
      cover, keeps `[video.0]` key order and every other section byte-identical. 15 keys differed from
      the shipped `/oem/usr/share/rkipc-imx415-720p.ini`. Verified: all 15 other sections compare equal.
- [x] **9.2** Installed `/userdata/{rkipc_custom.ini,start_camera.sh,S99startcamera}` and confirmed
      they survive a reboot with unchanged hashes. The step-6 hook ships **inert** — the guide stops
      at "run it manually", so it activates only if copied into `/etc/init.d/`.
- [x] **9.3** Fixed the guide's step 5: `rkipc` and `librockit.so` are on `PATH`/`LD_LIBRARY_PATH` only
      through `/etc/profile.d/RkEnv.sh`, which a non-login shell never sources — the guide's command
      died with `rkipc: not found`. The wrapper sources it first, exactly like `/etc/init.d/S21appinit`.
- [x] **9.4** Encoder effect measured end to end over RTSP: 86 kbps → **2.19–2.32 Mbps**, `normal` →
      **High** profile, IDR every **25 frames exactly**, delivered 1280x720 **27.5 fps**, ISP work per
      frame 37 ms → 6 ms, `frameloss:0` / `all err count:0` across 34 219 frames. Frame sanity
      `YAVG 96.6`, `UAVG 128.1`, `VAVG 128.4`; decoded Laplacian variance 1528 → 4595, so the QP cap
      really is preserving detail rather than just spending bits.
- [x] **9.5** **Corrected step 4's premise by photography.** `1284x720` is a centre window of the array:
      it *magnifies* ~1.2–1.6× and drops scene that the 8MP mode's `3072x1728` crop keeps
      (`image/log/fov_left-8mp-crop_vs_right-native-1284x720.png`; reverting reproduces the wide
      framing to mean pixel diff 2.87). `media-ctl`'s `crop.bounds` is per-readout, so it cannot show
      this. Added a `MODE=native|8mp` switch to `start_camera.sh`, defaulting to the guide's `native`.
      Two measurement attempts were invalid first — an 80×19 correlation that scored high at every
      scale, and a gradient metric with an off-by-one stride — recorded so they are not repeated.
- [x] **9.6** Corrected a number I had propagated: the 8MP mode delivers **~20 fps** (248 CIF frames
      in 12 s, `rate:48ms`) although its format string says `@10000/150000` = 15 fps. Mode strings are
      nominal; `FLASH.md` updated. Also noted that rkipc rewrites its ini on exit, so the custom
      profile returns re-formatted after a reboot (md5 changes, all 15 values survive), and that the
      stream overshoots the requested 25 fps to the mode's ~27.7 fps ceiling.

### 9.7 — "VLC can't open the stream" investigated on the player side (2026-10-18)

Reported symptom: rkipc is running, VLC shows nothing. Nothing was wrong on the board, and the
investigation produced a working access procedure plus a checker (`scripts/watch_stream.sh`):

- [x] **Reproduced success with the real client**: VLC 3.0.23 on the workstation opens
      `rtsp://<board>:554/live/0` over **both** TCP (`--rtsp-tcp`) and its default UDP — log shows
      `Received first picture`, VideoToolbox h264 decode, `g711` 8 kHz audio, `Decoder wait done in
      94 ms`. UDP is fine on this network, so "force TCP" is a fallback, not the fix.
- [x] **Found the silent failure path**: this server answers `DESCRIBE /live/1` with **200 OK but
      streams zero bytes**, so a player pointed there opens and shows black with no error — the exact
      shape of the complaint. `/stream0` and `/` return `454 Session Not Found`, which VLC surfaces as
      "VLC is unable to open the MRL". Only `/live/0` streams.
- [x] **Ruled out session starvation**: six concurrent clients all received media (382–497 KB canary
      captures each), and a fresh client was served 2 s after all six were `SIGKILL`ed. So killed
      clients leave no blocking ghost sessions and rkipc never needs a restart for a stuck player.
- [x] **Two measurement traps I fell into, now documented**: `ffmpeg -t N -f null -` does not reliably
      terminate against this server (it sat ESTABLISHED and idle, which reads exactly like a dead
      camera), and macOS has no `timeout` binary — so probes must capture to a file and bound
      themselves with background-and-kill.
- [x] **Re-measured delivery**: 1253–1304 kbps at 26.5–27.3 fps. Below the ini's 2048 kbps target
      because a static scene lets Rockchip's CBR undershoot; the ceiling, not the floor. Not a fault.
      A later run measured **2004 kbps at 24.5 fps**, on target, once 3A had fully converged.

### 9.8 — The same complaint again, and this time the cause was mine (2026-10-18)

Second report of "VLC is unable to open the MRL", which turned out to be **two separate causes**, one
in the URL and one in a script I had written:

- [x] **The URL**: `rtsp://10.15.116.18:554/video/0`. Wrong host *and* wrong path. `10.15.116.18`
      answers nothing (100 % packet loss; the board is `10.15.116.182`), and `/video/0` is not a path
      this firmware serves — measured `DESCRIBE /video/0` → `454 Session Not Found`, same as
      `/stream0` and `/`. Only `/live/0` streams. Added `/video/0` to the path table and to the
      checker's probe list, since it is the path other Rockchip SDKs use and will keep being tried.
- [x] **My bug**: `start_camera.sh` launched rkipc as `"$RKIPC" … &` — backgrounded but **not
      detached**. Started over ssh, the pty is destroyed when the command returns, SIGHUP reaches the
      session, and rkipc dies. Caught it red-handed: `pidof rkipc` empty with **uptime still running**
      (6968 s, no reboot) and `dmesg` showing `venc_release` / `vrgn_release` / `vsys_release` /
      `s_power 0` ~100 s after my session closed — i.e. "rkipc appears to be running" from an old
      `ps`, but `0.0.0.0:554` gone and every path refused. Fixed with `nohup setsid … < /dev/null &`
      (both binaries confirmed present on the board), verified by `ppid=1 pgrp=3133 sid=3133` —
      a session leader adopted by init, which survived the ssh session closing and kept streaming.
      rkipc's own output now goes to `/tmp/rkipc.log` instead of a pty that vanishes.
- [x] **Lesson recorded**: the symptom "rkipc is running but the stream is refused" has a third cause
      besides path and route — **rkipc died after its launcher exited**. Check `pidof rkipc` and the
      `0.0.0.0:554` listener in `/proc/net/tcp`, not `ps` output remembered from earlier.
- [x] Fixed a portability bug found while testing the checker: BSD `mktemp` needs the `X`s at the end
      of the template, so `mktemp /tmp/watch.XXXXXX.h264` fails with `File exists` on macOS; the
      checker now uses a `$$`-based name.





## Phase 7 field report — the DT node cannot be added at runtime (2026-10-17)

`camera_bringup.md` and task 4.5 both assumed a runtime configfs overlay would be enough. It is not.
Established by controlled experiment, not inference:

1. **Runtime configfs overlays are inert.** Applying `imx415-2lane.dtbo` to
   `/sys/kernel/config/device-tree/overlays/imx415/dtbo` returns success but does nothing; this kernel
   exposes a `status` attribute per overlay and it reads **`0`** (`pwm0m0`, applied at boot, reads `1`).
   Bisected with three purpose-built overlays — a 231-byte one adding a single plain node under
   `/i2c@ff470000`, and a trivial one adding a named node to the **root** node — both also `status=0`.
   The content of the overlay is irrelevant; `cat`/`dd` simply never report the kernel's refusal.
2. **This kernel has no I2C dynamic-DT hook.** `/proc/kallsyms` contains `of_reconfig_notify`,
   `of_platform_notify` and `of_i2c_register_devices`, but **no `i2c_of_notify` / `i2c_add_clients`**.
   The I2C core never subscribes to the reconfig chain, so an applied overlay can instantiate *platform*
   devices (which is exactly why the earlier PWM overlay worked) but can **never** create the I2C client
   at 0x37. `of_i2c_register_devices()` runs only from `i2c_register_adapter()`, in kernel init, before
   any userspace exists — so no init-script ordering can beat it.
3. **Therefore the node must live in the DTB the kernel boots from** = the on-flash DTB, i.e. Luckfox's
   *static* route (`/mnt/cfg/fdt_overlay/*.dts` → `fdtoverlay` merges into `/dev/mtdblock3` + republishes
   the FIT `data-size` and sha256). `/dev/mtdblock3` is mtd "boot"; the kernel's own DTB region is
   bytes `[2048, 38196)` and the **kernel image starts at 38400 → only 204 bytes of headroom**.
   `fdtoverlay` measures our overlay at **+641 bytes → 437 bytes too large.** Luckfox's script would
   print `Kernel will be affected !` and then `dd` unconditionally **over the kernel image**.
4. **The only way to make room** is to delete nodes the board cannot use — `/i2c@ff470000/sc4336@30`
   and `sc530ai@30` (this board has one sensor socket, holding an IMX415; `i2cdetect` shows nothing at
   0x30 and both probes fail at boot, which is why the firmware needs `clr_unready_dev`). Freeing the
   exact number of bytes still has to be measured on the target (host brew ships no `fdt rm`).
5. **Recovery material is ready:** the whole writable region (header + DTB, 38196 bytes,
   sha256 `7a6227a5…caac`) is backed up on the host at `/tmp/bk_region.bin` with the round-trip hash
   verified, so a restore is one `dd` — *provided the board still boots to offer it*.
6. Also confirmed: `i2cdetect -y 4` answers at **0x37** (Stage 1 passes; 0x1a is `--`, which
   `camera_bringup.md` would have misreported as a ribbon-cable fault).


---

## Risks / open questions — every one now settled by evidence

1. **Kernel version mismatch** (`files_to_get.md` assumed `5.10.110`, board runs `5.10.160`) —
   **not an issue**: `insmod imx415.ko` returns 0 with no `disagrees about version of symbol` and
   no `invalid module format`; the module probes and streams on `5.10.160`.
2. **"The `.ko` may be RV1106-specific"** — **not an issue**: it is a 32-bit ARM relocatable object
   with no `__versions` section (modversions off on this kernel), so vermagic is the only gate and
   it passes. It now drives the sensor on real RV1103 hardware.
3. **The 2-lane triangle (hardware + DT + driver)** — **resolved**: `data-lanes = <1 2>` is in the
   boot DTB and the driver agrees, logging `detect imx415 lane 2`. The sensor's I2C address is
   **`0x37`, not `0x1a`** as the bring-up note assumed; `i2cdetect -y 4` now shows `UU` there.
4. **"A 2-lane IQ profile may not exist"** — **moot in practice**: the Pico Zero IQ JSON loads and
   3A converges (exposure walks 2149→1912→1843→1604→1223 as the scene settles, AWBGAIN `ON`,
   neutral decoded chroma `UAVG 128.4 VAVG 128.2`). Image quality is untuned for this lens but the
   pipeline is genuinely auto-exposing on real frames.
5. **"Where our board's DT lives"** — **resolved**: the kernel DT is the FIT `fdt` image at LBA
   `0x800` in the `boot` partition, and that is what was rebuilt.
6. **Destructiveness** — the only destructive step was one whole-partition `flashcp`, verified by
   read-back, with a pristine copy both on the host and on the board at `/oem/usr/firmware/`.
7. **"`rkipc.ini` was not found"** — **resolved**: `RkLunch.sh` synthesises `/tmp/rkipc-factory-
   config.ini` as a symlink and copies it to `/userdata/rkipc.ini` each boot, so the file is never
   at the paths the note checks. The missing piece was only the `imx415` branch in its selector.
8. **Frame rate — CLOSED, with a finding that overturns the guide's premise.** Forcing the driver's
   native `1284x720` mode with `media-ctl` raises the stream from ~20.7 to **27.5 fps** (and ISP work
   from 37 ms to 6 ms per frame), so 30 fps-class delivery is available — but `1284x720` is a **centre
   window** of the array, not a full readout: it magnifies ~1.2–1.6× and loses scene the 8MP mode's
   `3072x1728` crop keeps. `start_camera.sh` therefore exposes both as `MODE=native` / `MODE=8mp`.
   Evidence, measurements and the two invalid measurement attempts it took to settle: 
   `configuration_guide.md`.

## Appendix — verified target board state (probed read-only, 2026-10-17)

| Item | Value |
|---|---|
| Hostname / kernel | `luckfox`, `Linux 5.10.160 #22 armv7l` |
| Distro | Buildroot 2023.02.6 (`-g2ae728b52-dirty`) |
| Filesystems | `/` ubifs `ubi0:rootfs` rw; `/oem` ubifs rw; `/userdata` ubifs rw |
| RAM | 33.6 MB total, ~16 MB available |
| Sensor `.ko` present | `mis5001.ko`, `sc3336.ko` only — **no `imx415.ko`** |
| `insmod_ko.sh` | already contains `__insmod imx415.ko`, ahead of `video_rkcif.ko` |
| IQ files present | `mis5001_CMK-OT2115-PC1_30IRC-F16.json`, `sc3336_CMK-OT2119-PC1_30IRC-F16.json`, `sc4336_OT01_40IRC_F16.json` — **no imx415** |
| Loaded camera stack | `video_rkcif`, `video_rkisp`, `phy_rockchip_csi2_dphy(_hw)`, `rockit`, `rk_dvbm`, `rga3`, `mpp_vcodec` |
| I2C buses | `/dev/i2c-4` only (matches `camera_bringup.md` Stage 1) |
| dmesg | `rkcif-mipi-lvds: clear unready subdev num: 3`, `get remote terminal sensor failed` → no sensor bound |
| Host (this Mac) | Apple Silicon, brew prefix `/usr/local`; images are ext4; no `debugfs`/`e2tools`/`dtc`/`sshpass` installed; Docker CLI present, daemon not running |

---

## Status snapshot as of Phase 6 (2026-10-17) — Phases 7 and 8 have since completed; final status at the end of this file

This section is kept as the record of what was known before deploying. Its "nothing was written to
the board" sentence describes Phase 6 only; the board has since been flashed and verified.

All artifacts are in `extracted/imx415/`; provenance, checksums and full reasoning are in
**`extracted/imx415/MANIFEST.md`**. Source images re-hash identical to baseline, and **nothing was
written to the board** — the only device access was read-only inspection plus a
`base64 /sys/firmware/fdt` dump.

Four findings below **correct the assumptions** this tasklist and `camera_bringup.md` started from:

1. **`insmod` compatibility is not a risk — it is settled.** vermagic matches exactly
   (`5.10.160 mod_unload ARMv7 thumb2 p2v8`), `CONFIG_MODVERSIONS` is off (no `__versions` section),
   and seven shared modules are **sha256-identical** between the Pico Zero image and our board, so
   the two firmwares are the same SDK build. Risk 1 and 2 are closed.
2. **`camera_bringup.md` Stage 1 watches the wrong I2C address.** The Luckfox IMX415 module is at
   **`0x37`**, not `0x1a` — `i2cdetect -y 4` must be read at 0x37.
3. **A DT node is mandatory, and none exists.** Our live DT declares only sc3336/sc4336/sc530ai, so
   `imx415.ko` alone can never probe. Delivered as `dtb/imx415-2lane.dts` + `.dtbo` for a **runtime
   configfs overlay** (available and `rw` on our board) — this closes open question 5, no reflash.
4. **The 1080p binned goal is not reachable as sensor-native binning.** Resolved through the
   driver's own relocations: `supported_modes_2lane` contains only 3864x2192 (10-bit and 12-bit,
   891M) and 1284x720 — the `1932x1096` mode exists only in the 4-lane array. Stage 4's `1920x1080`
   must therefore be ISP-scaled from 8MP, or drop to 720p. **This needs a decision from you.**

New open item replacing risks 1/2/5: **what frequency is xvclk on our board?** The reference design
supplies the IMX415 with a 37.125 MHz oscillator; our DT routes CRU xclk instead, and the driver
validates it (`xvclk mismatched`). Risk 4 (IQ tuning quality) and risk 6 (power-cut during writes)
stand, and risk 7 is resolved by artifact D (`rkipc-imx415-500w.ini`).

---

## FINAL STATUS — Phases 0–9 complete; camera running on hardware (2026-10-18)

The xvclk question raised immediately above is now **closed**: no clock-failure path in the driver
fires, and the sensor streams, which a wrong input clock makes impossible. The board at
`10.15.116.182` boots the rebuilt `boot` partition and serves 720p RTSP with no manual step:

```
imx415@37 in the booted DTB -> detect imx415 lane 2 -> Detected imx415 id 0000e0
  -> dphy0 matches m00_b_imx415 4-0037 -> sensor@3864x2192@12bit -> CIF crop 3072x1728
  -> rkisp_mainpath NV12 1280x720, frameloss:0, ErrCnt:0, 17563 frames, csi size err:0
  -> rkipc auto-started at boot -> rtsp://<board>:554/live/0  h264 1280x720 ~20.7 fps + pcm_alaw
```

Phase 9 added the encoder profile on top, so the running configuration is now:

```
/userdata/start_camera.sh (MODE=native)
  -> sensor 1284x720@10000/900000 -> ISP Dcrop(0,0|1280x720), 6 ms/frame
  -> h264 High, 2.19-2.32 Mbps CBR, QP<=34, IDR every 25 frames, 27.5 fps, frameloss:0
```

Rollback is `adb push boot-original-backup.img /tmp/ && adb shell 'flashcp -v /tmp/boot-original-backup.img /dev/mtd3; reboot'`,
and a copy of the original partition is stored on the board itself under `/oem/usr/firmware/`. The
Phase 9 changes need no rollback procedure: they live only in `/userdata`, and a `reboot` restores the
stock pipeline.

Only two things remain optional:

* **Framing vs frame rate** — `MODE=native` gives 27.5 fps with ~1.2–1.6× less field of view,
  `MODE=8mp` gives the widest view at ~20 fps (see risk 8 and `configuration_guide.md`).
* **Image quality** — the IQ JSON is still the Pico Zero module's tuning: loaded and functioning,
  never tuned for this lens/sensor combination. A proper tuning pass is its own project.






