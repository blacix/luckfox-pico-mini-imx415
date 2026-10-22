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

1. **Review the patched IMX415 driver and define the required sensor modes.**
   Use the driver from `Luckfox_Pico_Zero_EMMC_250802_extract/` and compare
   its mode table with the SDK's `imx415.c`. The extracted project contains a
   compiled module rather than the patched source, so inspect its available
   mode-table evidence as well as the SDK source. The current extraction report
   lists three 2-lane modes: two 3864x2192 readouts and a 1284x720 readout; the
   1932x1096 binned mode appears in the 4-lane table, not the 2-lane table.

   Resolve and document:

   - whether the current 720p stream uses the sensor's narrow 1284x720 window
     or reads a wider sensor mode and crops/scales it downstream;
   - what “2K” should mean for this project (for example, 2560x1440 or
     2048x1080), and whether the desired Full HD and 2K outputs should retain
     the full field of view;
   - which sensor readout/binning modes, CSI-2 bandwidth, frame rates, and
     downstream CIF/ISP crop or scale operations can meet those output goals.

   **Deliverable:** a mode table and a concrete driver-change specification
   for Full HD and, if feasible, the selected 2K target. Do not change the
   driver, device tree, or `rkipc` profiles until that specification is
   agreed.

2. **Keep camera startup aligned with build selection.** `S99a-eye-cam` uses
   an IMX415-specific profile. Ensure it only replaces the stock `rkipc`
   process in an IMX415 build; an SC3336 build must keep its stock camera
   configuration.
3. **Validate the full IMX415 capture path.** Confirm sensor probe and media
   links, capture frames through V4L2, then verify the `rkipc` RTSP stream with
   the selected profile and mode from task 1. Record the actual stable
   resolution, frame rate, field of view, and latency on the RV1103G.
4. **Confirm hardware details.** Verify the module's power/reset wiring and
   operating modes against the working hardware. Keep any unverified
   electrical assumptions explicit in the device-tree comments.
5. **Validate a clean full-image update.** Build and flash an `imx415` image,
   confirm the device tree selects only IMX415 on the intended D-PHY input,
   and check that the module, service, INI, and IQ file are present after boot.

Changes to the driver binary, camera INI/IQ files, or deployed service scripts
can be tried with `./deploy.sh` when the running image's kernel ABI and device
tree are already suitable. Device-tree, kernel configuration, SDK integration,
or other build-time changes require `./build.sh imx415` and flashing the
resulting image before they can be validated.

