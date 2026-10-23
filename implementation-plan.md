## Current implementation plan

The initial bring-up plan is superseded by the current integrated setup below.
Use this plan for remaining work; it distinguishes files that can be tested
through ADB from changes that require a complete image build and flash.

### Implemented

- The root `build.sh` selects `sc3336` or `imx415`, synchronizes tracked kernel
  and rootfs inputs into the SDK, and builds/packages the full image.
- The tracked device tree keeps both camera definitions and switches the
  selected sensor and its D-PHY input in the SDK copy at build time.
- The kernel defconfig enables both camera drivers as modules, and the full
  image packages them under `/oem/usr/ko/`.
- The IMX415 `rkipc` INI profile and matching IQ JSON are tracked in `camera/`
  and copied into the image overlay at `/usr/share/`.
- `S99a-eye-cam` stops the stock `rkipc` process and starts it with the tracked
  IMX415 INI and IQ directory; its startup on the device has been tested and
  works. `S99a-eye` runs the PWM LED test.
- `deploy.sh` provides an ADB-based iteration path for changed module,
  userspace configuration, and service files without rebuilding the complete
  image.

### Remaining work

1. **[IN PROGRESS] Add a two-lane, full-field Full HD sensor mode and scale it
   to 720p in the application.** The target is the Luckfox Pico Mini with its
   RV1103G SoC and two-lane CSI-2 connection. The sensor should use full-array
   2x2 binning; the camera pipeline should feed that binned frame to the ISP,
   which produces the application's 1280x720 output without the narrow field
   of view of the 1284x720 sensor window.

   **Platform and mode evidence:**

   - The extracted custom firmware has run on this Pico Mini target. It
     validates the existing two-lane sensor → D-PHY → RKCIF → RKISP route:
     the sensor captures 3864x2192, CIF/ISP report a 3072x1728 input, and
     RKISP delivers 1280x720 without reported frame or CSI-size errors. This
     is a useful board baseline, but it does not validate a binned 1080-class
     mode.
   - The extracted driver's `mode_report.txt` lists three entries in
     `supported_modes_2lane[]`: 3864x2192 RAW12, 1284x720 RAW12, and 3864x2192
     RAW10. Its binned register table is associated with the other mode list.
     The tested 1284x720 path is a center window and narrows the field of view.
   - The SDK source has a candidate table named
     `imx415_linear_12bit_1932x1096_594M_regs`. Its current 4-lane mode record
     reports 1944x1097, and `imx415_get_selection()` maps that size to a
     1920x1080 crop rectangle. The table name, sensor transmission size,
     driver's reported pad size, and selected crop are therefore distinct
     values and must not be treated as synonyms.
   - The draft register sequence in the extracted `instructions.md` is a
     proposal, not validated mode data. The INI's 1280x720 encoder settings
     do not select a sensor mode by themselves.

   **Code review and implementation steps:**

   1. **Establish the exact two-lane sensor mode.** Review the candidate
      register table and its use in `supported_modes[]` in `camera/imx415.c`;
      compare every relevant setting with a reliable IMX415 register source
      and the known-good Pico Mini driver/image. Confirm binning enable,
      CSI-2 lane and RAW format settings, register ordering, transmitted
      dimensions, crop origin/margins, XVCLK, line/frame timing, and a
      feasible two-lane link rate. Do not copy the draft list or assume the
      candidate 4-lane table is valid unchanged on two lanes.
   2. **Add the mode to the two-lane mode table.** Add a dedicated mode
      register array if the verified sequence differs by lane count, then add
      a linear (`NO_HDR`) record to `supported_modes_2lane[]` while preserving
      the current 8MP and 1284x720 entries. Populate `bus_fmt`, width/height,
      `max_fps`, `hts_def`, `vts_def`, `exp_def`, `mipi_freq_idx`, `bpp`,
      register pointers, VC, and `xvclk` from the validated mode. Check that
      the Pico Mini clock and link rate support the chosen timing; do not
      carry over the candidate 4-lane record's values without validation.
   3. **Audit the driver code paths that consume mode metadata.** In
      `imx415_probe()`, two endpoint lanes select `supported_modes_2lane[]`.
      `imx415_find_best_fit()`/`imx415_set_fmt()` pick the nearest size and
      update current mode; `imx415_enum_frame_sizes()` and
      `imx415_enum_frame_interval()` expose the table; `imx415_open()` uses
      entry zero as the default. Verify a 1920x1080 request selects the new
      binned mode deterministically, and decide explicitly whether default
      mode ordering should change. Check `imx415_set_fmt()` and
      `imx415_initialize_controls()` for HBLANK, VBLANK, exposure limits,
      link-frequency, and pixel-rate consistency. Also check the dimensions
      and control updates in `RKMODULE_SET_HDR_CFG` within `imx415_ioctl()`.
   4. **Define sensor-pad and crop dimensions deliberately.**
      `imx415_get_selection()` currently returns a 1920x1080 crop only when
      mode metadata is 1944x1097; other sizes return unchanged dimensions.
      Determine whether the verified binned transmission uses that existing
      padded-size convention or requires a new selection case. The crop may
      remove only documented/alignment margins, not active pixels; confirm
      its origin and field of view from capture. Inspect actual Pico Mini
      RKCIF and RKISP rectangles, since the sensor subdevice callback alone
      does not prove the downstream crop behavior.
   5. **Keep board integration specific to the Pico Mini.** The tracked DTSI
      already connects IMX415 to D-PHY input 3 with two data lanes and the
      board's CRU MIPI camera clock. The extracted working firmware confirms
      this graph works on the target, so no DTSI change is planned unless
      mode negotiation demonstrates a missing board-level setting. Keep the
      tracked INI encoder output at 1280x720; establish whether RKISP/rkaiq
      negotiates and scales the new binned input before changing the INI or
      IQ JSON.
   6. **Build and validate each pipeline boundary on the Pico Mini.**
      `build.sh imx415` copies tracked `camera/imx415.c` into the SDK kernel
      tree before building. Compile the driver, then verify the selected
      sensor mode and independently record sensor-pad, CIF, ISP-input,
      ISP-output, and encoder formats. Capture a still and confirm the RTSP
      output remains 1280x720. Compare scene edges with the known-good
      3864x2192 baseline, and record stable frame rate, memory pressure,
      frame-loss counters, and CSI-size errors. The extracted firmware is a
      tested board baseline for the existing route, not proof of the new mode.

   **Deliverable:** a validated two-lane binned mode in the tracked driver,
   exposed as a 1920x1080 active frame with explicit handling of any sensor
   margins, plus Pico Mini evidence that the pipeline scales it to a
   full-field 1280x720 stream without capture errors.

   2K is outside this project's goal. Keep the work focused on the full-field
   Full HD sensor input and its crop-free 1280x720 application output.

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

