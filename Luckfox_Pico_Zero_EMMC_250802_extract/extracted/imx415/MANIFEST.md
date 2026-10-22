# IMX415 extraction manifest

Extracted 2026-10-17 from `../../Luckfox_Pico_Zero_EMMC_250802/` for our custom RV1103 board.
Extraction was **read-only**: all eight source images re-hash identical to
`_work/source_hashes.txt` (`shasum -c` → all `OK`). Nothing was written to the target board.

Host tools installed for this: `brew install e2tools e2fsprogs dtc`
(`debugfs` is keg-only at `/usr/local/opt/e2fsprogs/sbin/debugfs`). No macFUSE / kernel extension.

## Artifacts required by `files_to_get.md`

| | File | Size | sha256 (16) | Source inside image | Goes to |
|---|---|---|---|---|---|
| A | `iqfiles/imx415_CMK-OT2022-PX1_IR0147-36IRC-8M-F20.json` | 451241 | `5d56044f9bc8c526` | `oem.img` → `/usr/share/iqfiles/` | `/etc/iqfiles/` **and** `/oem/usr/share/iqfiles/` |
| B | `ko/imx415.ko` | 26844 | `3a44c6edb2fa4de1` | `oem.img` → `/usr/ko/` | `/oem/usr/ko/` |
| C | `dtb/imx415-2lane.dts` + `.dtbo` | — / 1324 | `0a72f15ab5eac8f5` / `9cf0ac66ee367661` | authored from `boot.img` DTB vs. live board DT | configfs overlay at runtime |
| D* | `ko/rkipc-imx415-500w.ini` | 15785 | `930df8c97cbe511b` | `oem.img` → `/usr/share/` | `/userdata/rkipc.ini` (edit to 1080p first) |

\* D is an extra found during extraction: `camera_bringup.md` Stage 4 looks for a `rkipc.ini` and
our board has **none at either path it checks**, so it had to come from the source image too.

Note the image-internal paths: `oem.img` **is** the `/oem` filesystem, so its root is `/usr/...`,
not `/oem/usr/...` as written in `files_to_get.md`.

## Verdict on artifact B — drop-in usable, no recompile needed

Evidence (see `_work/elf_report.txt`, `_work/mode_report.txt`):

* `imx415.ko` is **ELF 32-bit ARM relocatable**, `vermagic=5.10.160 mod_unload ARMv7 thumb2 p2v8`
  — byte-for-byte the same vermagic as our board's kernel (`uname -r` = `5.10.160`).
* **No `__versions` section in any of these modules** → kernel built *without*
  `CONFIG_MODVERSIONS`, so there is no symbol-CRC pinning; vermagic alone decides, and it matches.
* The two firmwares are effectively the **same SDK build**: `mis5001.ko`, `sc3336.ko`,
  `video_rkcif.ko`, `phy-rockchip-csi2-dphy.ko`, `phy-rockchip-csi2-dphy-hw.ko`, `rk_dvbm.ko`
  and `rockit.ko` are **sha256-identical** between the Pico Zero image and our board.
  (`video_rkisp.ko` is the one exception — it differs, but it is already loaded and working here,
  and `imx415.ko` depends on nothing: `depends=` is empty.)
* Our board's `/oem/usr/ko/insmod_ko.sh` **already calls `__insmod imx415.ko`**, so persistence is
  just copying the file into place.

**Bucket (a): drop-in.** Copy to `/oem/usr/ko/imx415.ko` and `insmod`.

## Verdict on artifact A — matched by name, and the naming is load-bearing

rkaiq selects the tuning file from the DT strings, not by scanning: the filename is
`<driver>_<rockchip,camera-module-name>_<rockchip,camera-module-lens-name>.json`. The reference
DTB declares `CMK-OT2022-PX1` + `IR0147-36IRC-8M-F20`, which is exactly this filename. It declares
`sensor_calib.resolution = 3840x2160` and uses the same schema as the IQ files already on our board
(`sensor_calib`/`module_calib`/`main_scene`/`uapi`), so our rkaiq can consume it. The source ini's
`[isp]` section carries **no `iq_file_dir` key**, so rkipc uses its built-in default — put the JSON
in **both** candidate directories to be safe.

## Artifact C — why an overlay is needed, and what it changes

Our board's live DT (pulled read-only into `_work/target_fdt.dtb`, decompiled as
`dtb/target_live.dts`) contains **no imx415 node at all** — only `sc3336@30`, `sc4336@30` and
`sc530ai@30` on `i2c@ff470000`. `imx415.ko` matches on the `sony,imx415` compatible, so **without a
DT node it can never probe**, no matter what else is done right. Good news: `/sys/kernel/config`
is mounted `rw` and exposes `device-tree/overlays`, so this applies at runtime — no reflashing.

What the overlay changes versus the Pico Zero reference node:

| Property | Pico Zero (RV1106) | Our overlay | Why |
|---|---|---|---|
| `data-lanes` (both ends) | `<1 2 3 4>` | **`<1 2>`** | RV1103 D-PHY has 2 data lanes; driver prints `detect imx415 lane %d` and installs `supported_modes_2lane` |
| I2C `reg` | `0x37` | `0x37` | the Luckfox module's 7-bit address — **not 0x1a** |
| xvclk | `/out-osc-imx415` fixed-clock `0x2367b88` = **37.125 MHz** | CRU xclk `<&cru 0xa5>` + `pinctrl mipi-refclk-out0` | our DT has no oscillator node; copied from our own sc3336 node |
| reset | `reset-gpios` gpio@ff550000 pin 21 active low | same | same physical camera-FPC reset pin on both boards |
| dphy endpoint | `port@0/endpoint@1` | new `endpoint@3` | `endpoint@0/1/2` are taken by our three sensors |
| `lens-focus` | `<&cam_ircut>` | omitted | no ir-cut on our board |

Built with `dtc -@ -I dts -O dtb` → exit 0, no substantive warnings. The only warnings are the
standalone-validation kind (`dtc` cannot see our base DT's `#address-cells` or the literal phandles
`0x02`/`0x31`/`0x32`); the base DT has no `__symbols__` node, so numeric handles are written out
directly and the kernel resolver renumbers only the two phandles created inside the overlay
(`__local_fixups__` confirms this).

## The two things that can still stop this bring-up

1. **Sensor clock frequency (hardware).** `imx415.ko` calls `clk_set_rate()`/`clk_get_rate()` on
   xvclk and logs `xvclk mismatched`. The reference design feeds the IMX415 **37.125 MHz**. If our
   CRU xclk output on that pin is 24/27 MHz the sensor will not stream — check our schematic; if
   needed, add a `fixed-clock` node the way the reference DT does.
2. **There is no 1080p-binned mode in 2-lane (driver fact, not opinion).** `camera_bringup.md` asks
   for 1080p 2x2 binning. Resolving the driver's relocations (`_work/mode_report.txt`) shows the
   4-lane `supported_modes` array has **10 entries** including
   `imx415_linear_12bit_1932x1096_594M_regs` (the ~1080p binned mode), whereas
   `supported_modes_2lane` has only **3**:
   * `imx415_linear_12bit_3864x2192_891M_regs_2lane`
   * `imx415_linear_10bit_3864x2192_891M_regs_2lane`
   * `imx415_linear_12bit_1284x720_2376M_regs_2lane`

   With 2 lanes the sensor therefore runs **8MP scaled down by the ISP** to reach 1080p output, or
   **1284x720** — the native 1932x1096 binned mode is not available, and 8MP over 2 lanes costs frame
   rate. Size `rkipc.ini` accordingly.

## Apply order (Phase 7 — awaiting approval; nothing written to the board yet)

```sh
insmod /tmp/imx415.ko; dmesg | tail -25
mkdir /sys/kernel/config/device-tree/overlays/imx415
cat /tmp/imx415-2lane.dtbo > /sys/kernel/config/device-tree/overlays/imx415/dtbo
dmesg | tail -30; i2cdetect -y 4        # expect 0x37, NOT 0x1a
cp imx415_CMK-OT2022-PX1_IR0147-36IRC-8M-F20.json /etc/iqfiles/ && chmod 644 /etc/iqfiles/*.json
# then rkipc from rkipc-imx415-500w.ini, but first change [video.0] 3040x1710 -> 1920x1080,
# gop 50 -> 30, smart close -> 1 (RAM is ~16 MB free).  Undo overlay: rmdir .../overlays/imx415
```

## Helper scripts in `_work/` (dependency-free Python, reusable)

| Script | Purpose |
|---|---|
| `elf_sections.py` | ELF class/machine/type + section list; proves 32-bit ARM and no `__versions` |
| `carve_dtb.py` | carves every FDT out of a Rockchip `boot.img` (the DTB is not at offset 0) |
| `phandle_map.py` | maps `<0xNN>` phandles in decompiled DTS to node paths — how the overlay's clock/gpio/pinctrl handles were identified |
| `mode_array_relocs.py` | resolves a driver's mode arrays through **SHT_REL** records to the register tables they install |

## Superseded: the runtime-overlay plan above

The overlay route described earlier in this file does not work on this board and has been
replaced by the rebuilt image in `../../../image/`. Two independent reasons, both established by
experiment on the device:

* Writing a `.dtbo` to `/sys/kernel/config/device-tree/overlays/<name>/dtbo` reports success but
  applies nothing -- this kernel exposes a per-overlay `status` attribute and it reads `0`, and no
  node appears, even for a trivial overlay that only adds a named node to the root node.
* More fundamentally, the I2C client cannot be created after boot at all: `/proc/kallsyms` has
  `of_i2c_register_devices`, `of_reconfig_notify` and `of_platform_notify` but **no**
  `i2c_of_notify`/`i2c_add_clients`, so the I2C core never listens for device-tree changes and
  `of_i2c_register_devices()` only runs from `i2c_register_adapter()` during kernel init. A DT node
  therefore has to be in the DTB the kernel boots from; no init-script ordering can supply it.

`[video.0] smart` is also left at the reference tuning's `close` rather than the `1` sketched
above, and the resolution target is 1280x720, not 1920x1080.

## Phase 8 deliverables — `camera/image/` and `camera/scripts/`

Built offline into flashable files; no in-place patching of anything on the board's flash.

| File | Built by | Check |
|---|---|---|
| `image/boot-imx415.img` | `scripts/build_boot_img.py` | sha256 `9cda2058…`; DTB 36148 → 35704 B (648 B spare inside the 36352 B budget); 22146 of 4194304 bytes differ from the original and everything from `0x9600` (kernel) on is byte-identical; all three FIT hashes recompute to MATCH |
| `image/boot-original-backup.img` | read-only dump of `/dev/mtdblock3` | sha256 `ca17f335…`, verified against the board's own `sha256sum` of the mtd device |
| `image/oem/imx415.ko` | copy of the extracted module | sha256 `3a44c6ed…` on the host and in `/oem/usr/ko/` |
| `image/oem/imx415_CMK-OT2022-PX1_IR0147-36IRC-8M-F20.json` | copy of the extracted IQ file | 451241 B, installed as `/oem/usr/share/iqfiles/…` (`/etc/iqfiles` is a symlink to that directory) |
| `image/oem/rkipc-imx415-720p.ini` | `scripts/make_720p_ini.py` | every `[isp*]` tuning key carried over unchanged; only geometry changes |
| `image/oem/RkLunch.sh` | `scripts/patch_rklunch.py` | `sh -n` clean; installs as `a7e53159…`; the board's original is at `RkLunch.sh.bak` and hashes identical to the pristine pre-change copy `8d4ad13c…` |
| `image/provision_oem.sh` | hand-written | idempotent, one-time backup, re-verifies sizes and re-parses the script after install |
| `image/FLASH.md` | — | partition table with flash-sector offsets, flash and rollback procedure, `update.img` repack recipe |

| Script | Purpose |
|---|---|
| `scripts/build_boot_img.py` | the image builder: DTS node surgery through a brace/string-aware path scanner, DTB budget enforcement (it refuses to write an oversized image), FIT header regeneration, and self-verification |
| `scripts/verify_boot_img.py` | independent checker used to grade the builder's output, including the byte-level diff against the original |
| `scripts/fit.py` | reads/verifies/unpacks a Rockchip FIT boot partition |
| `scripts/make_720p_ini.py` | derives the 720p rkipc profile; refuses to edit unless every pattern matches exactly once (which caught `width = 3040` also matching inside `max_width = 3040`) |
| `scripts/patch_rklunch.py` | adds the missing `imx415` branch to the ini selector, in the right place (last match wins) |
| `scripts/provision_oem.sh` | installs the `/oem` payload on a board |

All three generators are reproducible: re-running each produces bit-identical output.

## Flashed and verified on hardware (2026-10-18)

`boot-imx415.img` is now the `boot` partition of the board at `10.15.116.182`, and the camera works
end to end: `imx415@37` in the booted DTB → `detect imx415 lane 2` → `Detected imx415 id 0000e0` →
`dphy0 matches m00_b_imx415 4-0037` → sensor at `3864x2192` 12-bit → CIF crop `3072x1728` →
`rkisp_mainpath` NV12 `1280x720` with `frameloss:0` → `rkipc` auto-started → RTSP on `/live/0`.
`i2cdetect -y 4` reports `UU` at `0x37`; `/proc/rkcif-mipi-lvds` shows 17 563 frames with
`csi size err:0` and `all err count:0`.

How it was written, since the obvious route does not work: `rkdeveloptool wl 0x800` fails with
`Write LBA failed!` (bulk LBA over SPI-NAND through the BootROM agent is unreliable from macOS —
its `rl` read also died at 75%), and on NAND a blind `wl` is unsound anyway because the vendor's own
`sd_update.txt` issues `mtd erase` before every `mtd write`. `adb push` + `flashcp -v /dev/mtd3`
from the board's Linux unlocked, erased, wrote with the kernel's real ECC scheme and verified.
The result was then confirmed independently: `sha256sum /dev/mtdblock3` on the board equals
`9cda2058…`, the intended image. Full procedure, evidence and rollback are in `image/FLASH.md`.

Both previously-open hardware questions closed in the affirmative: the CRU-routed xvclk is the
frequency the sensor expects (none of the driver's four clock-failure strings fire, and it
streams), and rkaiq runs the 8MP mode cropped to 720p rather than the native `1284x720` mode —
which is why the stream delivers ~20.7 fps against the ini's 30 fps request.



