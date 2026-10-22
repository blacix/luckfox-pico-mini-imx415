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

1. **Add a full-field Full HD sensor path, then scale to 720p in the
   application.** The requirement is that the sensor/pipeline deliver a
   full-field 1920x1080 image to the camera application, which resizes it to
   1280x720 for the output stream. The 720p output must retain the full scene
   field of view; do not meet the output size by selecting the sensor's narrow
   1284x720 center-window mode or by cropping the Full HD input.

   Findings from the extracted project:

   - `extracted/imx415/_work/mode_report.txt` identifies three modes in the
     extracted driver's 2-lane table: 3864x2192 RAW12, 1284x720 RAW12, and
     3864x2192 RAW10. It does not list a 1920x1080 2-lane mode.
   - The extracted project's `configuration_guide.md` identifies 1284x720 as
     a center window with reduced field of view. Its tested alternative reads
     3864x2192, then RKCIF crops to 3072x1728 before RKISP produces 1280x720;
     that path is wider than the center window but still crops the sensor
     image.
   - The extracted module has a 1932x1096 binned mode in its 4-lane table,
     not its 2-lane table. `instructions.md` proposes adding a 1920x1080
     2x2-binned mode for 2 lanes, but that proposal is not evidence that its
     register sequence or timing has been validated.
   - The INI output dimensions configure application streams; they do not by
     themselves select the sensor readout or guarantee a full-field path.

   Work through these steps before changing the implementation:

   - Compare the extracted module's mode-table evidence with the SDK driver
     source and identify reusable register tables, mode timings, bit depth,
     link frequency, and clock requirements. Validate any proposed binning
     registers against a reliable source; do not copy the draft register
     sequence without validation.
   - Define and implement a 2-lane sensor mode that reads the full active
     field into a roughly 1920x1080 image, if the sensor and RV1103 pipeline
     support it. Verify that RKCIF/ISP selection rectangles cover that entire
     image with no crop.
   - Configure the camera application to consume that Full HD input and
     resize it to a 1280x720 output. Verify the negotiated sensor, CIF, ISP,
     and encoder dimensions separately; INI output settings alone are not
     proof of the upstream mode.
   - Compare captured frames against the full-field reference and measure
     stable frame rate and frame errors.

   **Deliverable:** a reviewed mode table, the validated driver mode and
   pipeline changes, and a tested 1280x720 stream whose framing matches the
   full-field 1920x1080 input.

   2K is outside this project's goal. Keep the work focused on the full-field
   Full HD sensor input and its crop-free 1280x720 application output.

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

