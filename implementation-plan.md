## Current implementation plan

The initial bring-up plan is superseded by the current integrated setup below.
Use this plan for remaining work; it distinguishes files that can be tested
through ADB from changes that require a complete image build and flash.

### Implemented

- The root `build.sh` defaults to `imx415` and accepts `sc3336` explicitly;
  it synchronizes tracked kernel and rootfs inputs into the SDK and
  builds/packages the full image.
- The tracked device tree keeps both camera definitions and switches the
  selected sensor and its D-PHY input in the SDK copy at build time.
- The kernel defconfig enables both camera drivers as modules, and the full
  image packages them under `/oem/usr/ko/`.
- The IMX415 `rkipc` INI profile and matching IQ JSON are tracked in `camera/`
  and copied into the image overlay at `/usr/share/`.
- `S99a-eye-cam` stops the stock `rkipc` process and starts the tracked
  `/usr/bin/rkipc-supervisor.sh`, which retries `rkipc` after a fixed
  five-second delay if it exits. The previous direct launch worked on the
  device; the new retry behavior still needs target validation.
  `S99a-eye-led` runs the PWM LED test.
- `deploy.sh` provides an ADB-based iteration path for changed module,
  userspace configuration, and service files without rebuilding the complete
  image.

### Remaining work

1. **[IN PROGRESS] Implement two-lane Full HD binning on the Pico Mini.**
   The implementation target is the RV1103G Pico Mini, with full-array
   horizontal/vertical 2x2 binning and a 1920x1080 image passed through the
   ISP to a 1280x720 application stream. The specification below is ready
   for coding; the new mode still requires validation on the device.
   2K is outside the goal.

   **Evidence and selected design**

   The extracted custom firmware already runs on this Pico Mini and proves
   that the two-lane IMX415/D-PHY/RKCIF/RKISP route works. Its driver exposes
   3864x2192 RAW12, 1284x720 RAW12, and 3864x2192 RAW10 on two lanes. Its
   existing wide path crops the 8MP frame to 3072x1728 before producing
   720p; the small sensor mode narrows the field of view.

   Use Sony's IMX415-AAQR-C datasheet, rather than the extracted project's
   draft register instructions. The relevant references are page 49
   (binning timing limits), pages 57–58 (two-lane binning registers),
   page 61 (frame geometry), and page 80 (27 MHz / 891 Mbps clock settings).
   [Sony datasheet, hosted by Khadas](https://dl.khadas.com/products/add-ons/cameras/imx415/datasheet/imx415-datasheet.pdf)

   Select 27 MHz XVCLK and 891 Mbps per lane, matching the existing working
   two-lane RAW12 clock/link setup. Use 10-bit ADC conversion with RAW12
   transmission, as specified for binning. The mode supports a proposed
   maximum of 25 fps, derived from Sony's limits rather than a hardware-tested
   preset. Configure the normal operating profile for 20 fps to match the
   sensor timing observed on the current device; this does not lower the
   driver's 25 fps capability:

   | Parameter | Implementation value |
   | --- | --- |
   | Sensor pad format | SGBRG12_1X12, 1944x1097 |
   | Standard image selected by CIF | 1920x1080 |
   | ISP/application output | NV12 / encoded 1280x720 |
   | Mode | Linear, NO_HDR, VC0, full-array binning |
   | XVCLK | 27000000 Hz |
   | Lane bit rate / link frequency | 891000000 bps / 445500000 Hz |
   | HMAX / VMAX | 1100 / 2700 |
   | Sensor timing clock | 74250000 Hz |
   | Frame rate | 74250000 / (1100 × 2700) = 25 fps |
   | Driver pixel rate / HTS | 148500000 / 2200 |
   | HBLANK / default VBLANK | 256 / 1603 |
   | Default and minimum permitted VTS | 2700 (driver mode ceiling: 25 fps) |
   | Default exposure / maximum at default VTS | 2692 lines, leaving SHR0 = 8 |

   HMAX 1100 exceeds the documented two-lane binned minimum of 1024;
   VMAX 2700 exceeds the documented minimum of 2238. Keep the driver's
   existing maximum VTS, 0x7fff. Hardware validation must confirm the
   calculated timing and actual delivered frame rate.

   **1. Add the register array in camera/imx415.c**

   Create
   `imx415_linear_12bit_1944x1097_891M_regs_2lane[]` by copying the complete
   existing `imx415_linear_12bit_3864x2192_891M_regs_2lane[]` array.
   Retain its sensor tuning writes and the existing 891 Mbps MIPI timing.
   Apply the following explicit replacements/additions; do not append
   conflicting duplicate values later in the array.

   | Register(s) | Bytes to write, increasing address order |
   | --- | --- |
   | 0x3000, 0x3002 at array start | 0x01, 0x01 (standby; stop master) |
   | 0x3008–0x300b | 0x5d, 0x00, 0x42, 0x00 |
   | 0x301c | 0x00 (disable window cropping) |
   | 0x3020–0x3022 | 0x01, 0x01, 0x01 |
   | 0x3024–0x3026 | 0x8c, 0x0a, 0x00 (VMAX 2700) |
   | 0x3028–0x3029 | 0x4c, 0x04 (HMAX 1100) |
   | 0x302c–0x302d | 0x00, 0x00 (linear) |
   | 0x3031–0x3033 | 0x00, 0x01, 0x05 (ADC10, RAW12, 891 Mbps) |
   | 0x3050–0x3052 | 0x08, 0x00, 0x00 (initial SHR0) |
   | 0x30cf | 0x00 |
   | 0x30d9–0x30da | 0x02, 0x01 |
   | 0x3115–0x3116 | 0x00, 0x23 |
   | 0x3118–0x311b | 0xc6, 0x00, 0xe7, 0x00 |
   | 0x311e | 0x23 |
   | 0x3260, 0x3701 | 0x01, 0x00 (existing binned-mode settings) |
   | 0x4001 | 0x01 (two lanes) |
   | 0x4004–0x4005 | 0xc0, 0x06 |
   | 0x400c, 0x4074 | 0x00, 0x01 |
   | 0x4018–0x4019 | 0x7f, 0x00 |
   | 0x401a–0x401b | 0x37, 0x00 |
   | 0x401c–0x401d | 0x37, 0x00 |
   | 0x401e–0x401f | 0xf7, 0x00 |
   | 0x4020–0x4021 | 0x3f, 0x00 |
   | 0x4022–0x4023 | 0x6f, 0x00 |
   | 0x4024–0x4025 | 0x3f, 0x00 |
   | 0x4026–0x4027 | 0x5f, 0x00 |
   | 0x4028–0x4029 | 0x2f, 0x00 |

   Finish with the existing 0x3002 = 0x00, 30 ms delay, and REG_NULL.
   Leave standby asserted until `__imx415_start_stream()` has applied the
   V4L2 controls and writes 0x3000 = 0x00. Use SYS_MODE address 0x3033,
   consistent with the register map and vendor driver; the clock-table
   address printed as 0x3034 is inconsistent with those sources.

   Prevent settings leaking when switching back to existing modes:
   explicitly restore WINMODE, HADD/VADD/ADDMODE, ADBIT/MDBIT, VMAX,
   DIG_CLP/DIG_VLP, 0x3701, INCKSEL6/7, and MIPI timing high bytes in the
   corresponding two-lane arrays. Full-resolution modes restore binning
   off and their original timing; the 720p mode restores window mode and
   its original binning/timing. RAW10 and RAW12 must explicitly set MDBIT
   to 0 and 1 respectively. This is necessary because the existing arrays
   leave several values at reset defaults.

   **2. Register the mode and make the control metadata consistent**

   Append an exact 445500000 Hz entry to `link_freq_items[]`, with a named
   index constant for the new entry (index 5). Preserve existing indices;
   the current rounded 446000000 Hz entry would produce a different pixel
   rate. Add `u32 vts_min` to `struct imx415_mode`; zero retains legacy
   behavior and the new record sets it to 2700.

   Insert the new record first in `supported_modes_2lane[]` so probe and
   TRY-format defaults use the binned mode. Its fields are:
   `bus_fmt = MEDIA_BUS_FMT_SGBRG12_1X12`, `width = 1944`,
   `height = 1097`, `max_fps = {10000, 250000}`, `hts_def = 2200`,
   `vts_def = vts_min = 2700`, `exp_def = 2692`,
   `global_reg_list = NULL`, `reg_list = the new array`,
   `hdr_mode = NO_HDR`, `mipi_freq_idx = the new named index`,
   `bpp = 12`, `vc[PAD0] = V4L2_MBUS_CSI2_CHANNEL_0`, and
   `xvclk = IMX415_XVCLK_FREQ_27M`.
   Keep the three legacy two-lane modes and all four-lane entries.

   In `__imx415_start_stream()`, call the global-array writer only when
   `global_reg_list` is non-NULL. Continue checking errors from both
   nonempty global arrays and mode arrays. NULL is already used by the
   existing two-lane modes and currently produces a misleading error log.

   In `imx415_initialize_controls()`, `imx415_set_fmt()`, and the
   `RKMODULE_SET_HDR_CFG` branch of `imx415_ioctl()`, use
   `vts_min - height` as the VBLANK minimum when vts_min is nonzero.
   Preserve each path's existing minimum for legacy records. Update the
   exposure range/default for the selected mode before applying VBLANK;
   clamp a retained exposure to the new range so switching from this
   mode's 2692-line default to an old mode does not leave an invalid
   exposure default. Link-frequency and pixel-rate updates must report
   445500000 Hz and 148500000 pixels/s for the new mode.

   Enumeration remains driven by the table and ARRAY_SIZE.
   `imx415_find_best_fit()` should select the new RAW12 entry for a
   1920x1080 request and return its actual 1944x1097 pad dimensions.
   In `imx415_g_frame_interval()`, report the new mode's actual
   `cur_vts / 67500` seconds, including slower intervals caused by added
   blanking. Preserve legacy interval behavior.

   **3. Use explicit frame geometry and document the edge alignment**

   Keep the existing vendor convention: pad 1944x1097 and
   `imx415_get_selection()` crop bounds `(12, 8, 1920, 1080)`.
   This is the rectangle already produced for width 1944 by CROP_START.
   RKCIF's `rkcif_sync_crop_info()` consumes that rectangle, and
   `sditf_get_set_fmt()` reports its dimensions to the ISP. RKCIF requires
   RAW12 horizontal crop origins to be multiples of four.

   The Sony frame diagram contains recording pixels, processing margins,
   ignored pixels, and dummy pixels; 1944x1097 is not a second image
   resolution to encode. The vendor crop is an alignment convention, not
   proof that only dummy pixels are removed. Relative to the diagram's
   nominal recording origin, it can trim a few recording pixels at the
   edges. Record this limitation explicitly: the goal is full-array
   readout without the substantial zoom of the 1284x720 window, not a
   claim of zero-pixel-loss framing. Verify Bayer colors and scene edges
   on hardware before accepting this rectangle.

   **4. Select the mode explicitly before starting rkipc**

   Update `overlay/a-eye/etc/init.d/S99a-eye-cam`. After
   `stop_existing` succeeds, check that media-ctl is available and that
   the known Pico Mini sensor entity exists, then run:

   ```sh
   media-ctl -d /dev/media0 --set-v4l2 \
       '"m00_b_imx415 4-0037":0[fmt:SGBRG12_1X12/1944x1097]'
   ```

   Abort startup with a useful error if selection fails; otherwise use
   the existing rkipc command, INI, IQ directory, and logging.
   The stock Pico Buildroot defconfig already enables libv4l utilities,
   including media-ctl; verify the binary is packaged during the build.

   This step is required because the SDK's
   `common/isp/rv1106/isp.c:sample_common_isp_run()` calls AIQ prepare
   with width/height 0,0. The extracted project's successful manual mode
   selection provides the precedent. Check the active sensor format again
   after rkipc starts; if AIQ changes it, fail validation and record the
   override rather than claiming the mode was selected.

   **5. INI frame rate and IQ handling**

   Configure the main stream source and destination rates, both ISP
   adjustment rates, and the one-second GOP intervals for 20 fps in
   `camera/rkipc-imx415-720p.ini`. This matches the active device's observed
   20 fps sensor timing while preserving the driver's 25 fps maximum.

   Keep output dimensions 1280x720: the RV1103 IPC implementation sets the
   VI channel size from video.0 width/height, so ISP scaling occurs before
   encoding. Increasing these INI dimensions to 1920x1080 would instead
   change the application output and would require a separate resize path.

   Start with the working IQ JSON. Its sensor calibration references 4K,
   and its inspected normal-scene LSC block is disabled; those calibration
   references are not a sensor-mode switch. Do not replace every 4K string
   with 1080p. Check AIQ logs, exposure, white balance, black level, and
   shading in the binned mode. A demonstrated calibration mismatch needs
   a targeted IQ change with its own evidence.

   **6. Build, deploy, and acceptance checks**

   Implement the tracked driver, service selection, and agreed INI change;
   document the resulting pipeline and commands in README.md. Use
   `./build.sh imx415`, whose source synchronization is already implemented.
   No new SDK board variant, CMake change, or makefile integration is needed.
   For a compatible running image, `./deploy.sh` already installs the
   rebuilt module, service, INI, and IQ JSON; use a full image flash for
   final boot/packaging validation.

   Acceptance requires all of the following:

   - Driver builds for the Mini's configured kernel; runtime loads that
     rebuilt module and reports two CSI lanes with no clock mismatch.
   - Before and after rkipc startup, the sensor pad is RAW12 1944x1097,
     CIF crop is (12,8)/1920x1080, ISP input is 1920x1080, and ISP/RTSP
     output is 1280x720. Record media topology and /proc/rkcif-mipi-lvds,
     /proc/rkisp-vir0, and rkipc logs.
   - Link frequency, pixel rate, HBLANK, default VBLANK, and exposure
     limits match the specification. A requested faster frame rate cannot
     reduce VTS below 2700. Increasing VBLANK changes the reported interval.
   - With the proposed INI setting, measure approximately 25 distinct
     frames/s over at least 60 seconds, rather than trusting stream
     metadata. CIF/ISP error and loss counters do not increase, and the
     Mini does not run out of memory.
   - A captured image has correct colors and no dummy-pixel border,
     corruption, or narrow-window zoom. Use fixed scene landmarks. The
     extracted 8MP-to-3072x1728 image is already cropped and is only a
     comparison baseline, not proof of the full sensor field of view.
     Record the small vendor crop-alignment limitation separately.
   - Stop/start and reboot retain the chosen mode. Switching between the
     new mode and the existing RAW12 modes restores the correct binning,
     window, clock, and format settings without stale register values.

   **Completion:** mark this task complete only after the rebuilt driver
   and startup configuration pass those checks on the Pico Mini. Until
   then, the register/timing specification is a documented implementation
   candidate, not a validated camera mode.

2. **Keep camera startup aligned with build selection.** `S99a-eye-cam` uses
   an IMX415-specific profile. Ensure it only replaces the stock `rkipc`
   process in an IMX415 build; an SC3336 build must keep its stock camera
   configuration.
3. **Confirm hardware details.** Verify the module's power/reset wiring and
   operating modes against the working hardware. Keep any unverified
   electrical assumptions explicit in the device-tree comments.
4. **Validate a clean full-image update.** Build and flash an `imx415` image,
   confirm the device tree selects only IMX415 on the intended D-PHY input,
   and check that the module, service, INI, and IQ file are present after boot.

Changes to the driver binary, camera INI/IQ files, or deployed service scripts
can be tried with `./deploy.sh` when the running image's kernel ABI and device
tree are already suitable. Device-tree, kernel configuration, SDK integration,
or other build-time changes require `./build.sh imx415` and flashing the
resulting image before they can be validated.

