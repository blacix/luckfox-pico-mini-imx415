# Outstanding Implementation and Validation Plan

## Remaining work

### 1. Align camera startup with the selected build camera

`build.sh sc3336` currently selects the SC3336 device-tree node, but still
installs the IMX415-only `S99a-eye-cam`, `rkipc-supervisor.sh`, INI, and IQ file.
That service stops any running `rkipc` and launches it with the IMX415 settings.

Update the build's rootfs overlay selection so that:

- An IMX415 build installs the custom camera service, supervisor, INI, and IQ
  file, and the custom service owns the `rkipc` process.
- An SC3336 build omits those IMX415-only camera files and leaves the SDK's
  stock `RkLunch.sh` startup flow in control. The SDK flow selects
  `/oem/usr/share/rkipc-300w.ini`, copies it to `/userdata/rkipc.ini`, and
  starts `rkipc` with `/oem/usr/share/iqfiles` when it detects SC3336.
- The shared PWM LED test files remain available for either camera build. The
  LED init script's unconditional attempt to load `imx415.ko` should be removed
  or made camera-aware so the sensor-independent LED test also works on SC3336.

Verify the resulting SDK overlay contents for both `./build.sh imx415` and
`./build.sh sc3336` before building images. On the device, confirm only the
expected camera startup path owns `rkipc`.

### 2. Validate the 1080p sensor mode through the complete camera pipeline

The driver mode and 20 fps INI setting are implemented. The remaining work is
to validate that the selected mode survives application startup and produces a
stable, uncropped full-field image on the Pico Mini.

For an IMX415 image, build and flash the complete image, then verify:

- The loaded module is the rebuilt driver and the sensor is detected on two
  CSI-2 lanes without clock or link errors.
- The sensor pad is RAW12 1944x1097 and the CIF crop is `(left=12, top=8,
  width=1920, height=1080)` before and after `rkipc` starts. The ISP input is
  1920x1080 and the configured encoded/RTSP output remains 1280x720.
- If the mode does not remain selected after `rkipc` startup, set the media
  format before starting `rkipc` using the Pico Mini sensor entity, then repeat
  the before/after check:

  ```sh
  media-ctl -d /dev/media0 --set-v4l2 \
      '"m00_b_imx415 4-0037":0[fmt:SGBRG12_1X12/1944x1097]'
  ```

- Link frequency, pixel rate, HBLANK, VBLANK minimum, and exposure limits
  match the mode. VTS must not fall below 2700; increased VBLANK must change
  the reported frame interval.
- With the INI configured for 20 fps, measure approximately 20 distinct
  frames per second for at least 60 seconds. Do not infer delivered frame rate
  only from RTSP metadata. CIF/ISP error counters should remain stable, and the
  Mini should not run out of memory.
- Captured images have correct Bayer colors and no corruption, dummy-pixel
  border, or narrow-window zoom. Compare fixed scene landmarks. Record the
  small edge-alignment crop as a limitation: the 1944x1097 pad is aligned to
  the pipeline's 1920x1080 crop at `(12,8)`, so this is full-array binned
  readout without the 1284x720 window's substantial zoom, not a claim of
  zero-pixel-loss framing.
- Stop/start and reboot retain the mode. Switching between the new mode and
  existing two-lane modes restores their binning, window, clock, and format
  settings without stale register values.

The register-level description and mode table are in the README section
[IMX415 two-lane 1080p sensor mode](README.md#imx415-two-lane-1080p-sensor-mode).

## Build and deployment boundary

Use `./deploy.sh` for a changed module, camera configuration, or service when
the running kernel ABI and device tree already support it. Device-tree, kernel
configuration, SDK overlay selection, or other build-time changes require a
full image build with `./build.sh imx415` or `./build.sh sc3336` and flashing the
result before they can be validated.
