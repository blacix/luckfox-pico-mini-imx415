# Outstanding Implementation and Validation Plan

## Remaining work

### 1. Validate camera selection and `rkipc` startup

- Build once with `./build.sh imx415` and once with `./build.sh sc3336`.
- Inspect the SDK overlay after each build. Confirm the LED service remains in
  both; the camera service, supervisor, INI, and IQ file appear only for IMX415;
  switching from IMX415 to SC3336 removes stale project camera files.
- Boot each image and confirm the intended startup path owns `rkipc`. For
  IMX415, check whether the SDK launcher starts `rkipc` before the project
  service. For SC3336, confirm the stock launcher uses the SC3336 INI and OEM IQ
  directory.
- Observe `/tmp/rkipc.log` during a sustained IMX415 session. It is truncated
  between attempts but is not capped while `rkipc` runs; decide whether further
  limits are needed based on actual growth.

### 2. Validate the 1080p sensor mode through the complete camera pipeline

Build and flash the IMX415 image, then verify:

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
