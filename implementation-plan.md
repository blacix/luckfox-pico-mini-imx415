# Outstanding Implementation and Validation Plan

## Remaining work

### 1. Define a stock SC-camera build profile

The current `build.sh` accepts `imx415` or `sc3336`. The tracked DTSI disables
SC3336, SC4336, and SC530AI by default, while the SDK's stock startup script
contains INI-selection branches for all three SC sensors. The SDK DTSI backup
also had all three SC sensor nodes enabled. Decide how the project should
preserve this stock SC-camera support alongside its IMX415 profile.

- Review whether the stock flow is intended to detect whichever supported SC
  sensor is attached, or whether the build should select one exact SC sensor.
- Check the shared I²C address (`0x30`), MCLK, GPIO3 PC5, module index, and
  separate CSI inputs before deciding whether multiple SC nodes can safely be
  enabled together.
- Check that the tracked kernel defconfig builds the SC drivers required by
  the chosen stock-camera approach; it currently enables SC3336 and IMX415.
- Keep the IMX415 build's custom service, INI, and IQ file separate from the
  stock SC startup/configuration.

### 2. Validate camera selection and `rkipc` startup

- Build once with `./build.sh imx415` and once with `./build.sh sc3336`.
- Inspect the SDK overlay after each build. Confirm the LED service remains in
  both; the camera service, supervisor, INI, and IQ file appear only for IMX415;
  switching from IMX415 to SC3336 removes stale project camera files.
- Boot each image and confirm the intended startup path owns `rkipc`. For
  IMX415, check whether the SDK launcher starts `rkipc` before the project
  service. For SC3336, confirm the stock launcher uses the SC3336 INI and OEM IQ
  directory.
- With an IMX415 connected, confirm the supervisor loads the module and waits
  for `/sys/bus/i2c/drivers/imx415/4-0037` before starting `rkipc`. Also confirm
  that stopping the service interrupts the wait cleanly.
- Observe `/tmp/rkipc.log` during a sustained IMX415 session. It is truncated
  between attempts but is not capped while `rkipc` runs; decide whether further
  limits are needed based on actual growth.

### 3. Validate the 1080p sensor mode through the complete camera pipeline

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
- With the INI configured for 25 fps, measure approximately 25 distinct
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

## Automatic night mode — ongoing

Keep RKIPC running and retain continuous RTSP on the Pico Mini. Add V4L2
sensor-control measurement to the existing C++ service, with the current JPEG
measurement binary available as the alternative selected by a program
argument. RKIPC source changes, new RKIPC socket commands, and AIQ-context
integration are excluded from this work.

Existing JPEG processing, service supervision, GPIO/LED control, grayscale
switching, and their configuration are documented in the
[README](README.md). The tasks below cover outstanding work only.

### Live exposure and gain readback — investigate

- Validate that the sensor exposure/gain controls follow auto exposure as
  lighting changes while RKIPC streams. The successful SC3336 read is
  documented in the README's [exposure and gain section](README.md#reading-exposure-time-and-gain-while-rkipc-runs).
- Repeat readback on IMX415. Identify the sensor node dynamically and derive
  physical exposure/gain units for both sensors before calibrating thresholds.
- Assess the usefulness of exposure/gain measurements with the IR LED on,
  including reflective objects and changes in ambient lighting.

### Night-vision measurement calibration — ongoing

- Measure V4L2 exposure, gain, and score in bright and dark scenes on both
  SC3336 and IMX415. On IMX415, include the IR-cut and IR LED active together;
  those readings are not available yet.
- Revisit the initial V4L2 thresholds (100 to enter night, 500 to return to
  day) and LED score compensation (currently disabled) using those readings.
- Validate transitions in both directions, including ambient light returning
  while night mode is active and nearby reflective objects. Check continuous
  RTSP, sensor discovery, command failures, and resource use on the Pico Mini.
- Recheck JPEG luma thresholds separately if the JPEG measurement method is
  used; its thresholds are distinct from V4L2 score values.

**Deferred issue — conflicting exposure/gain triggers:** auto exposure can
maintain long exposure with low gain in a dark scene. Both additional rules
could therefore qualify in their respective states and cause repeated mode
changes. IR illumination can also lower gain enough to activate the day
trigger while ambient light remains low. Consecutive samples and the settling
delay filter transients but do not resolve persistent overlap. Proceed with
the requested thresholds first; measure these edge cases later and decide
whether further conditions or different thresholds are needed. No additional
conflict-resolution algorithm is selected for this first implementation.

### Characterize LED compensation versus output level and ambient light
Repeat the measurements in both a controlled light condition and a dark-room
condition. In each condition, hold the camera in night mode (night shutter
position and the same ISP night setting), keep the framing and scene fixed,
and collect repeated `night-vision-measurement` samples with the IR LED off,
at 10%, 50%, and 100% brightness. Allow exposure to settle after each LED
change and record the ambient-light condition, actual LED brightness,
`mean_y`, and `p90_y` in the measurement log. Use the LED-off result as the
baseline separately for each ambient-light condition, then compare the mean
increase at each output level. Fit a linear compensation from the 10% and 100%
measurements in each condition and use the 50% measurement to check the model.
Determine whether one linear model fits both conditions or if the LED effect
changes with ambient light. Adopt linear scaling only if the intermediate and
cross-condition results support it; otherwise retain a fixed estimate or use a
better-supported calibration.

### Remaining JPEG measurement issues

- **Snapshot ownership and completion:** the application selects the newest
  changed file from the shared snapshot directory. Concurrent manual/service
  captures can interfere, and unchanged size/timestamp observations are a
  completion heuristic. Establish exclusive capture ownership and avoid
  reading or deleting another request's snapshot without modifying RKIPC.
- **Failure cleanup:** a JPEG that fails decoding is left behind because
  deletion occurs only after successful processing. Define bounded cleanup
  for application-owned failed captures so repeated errors cannot accumulate
  files. Preserve the explicit `--keep-snapshots` diagnostic behavior.

### Validate on the Pico Mini

- Test day-to-night and night-to-day transitions, changing scenes, short light
  disturbances, and the effect of IR illumination on the measured brightness.
- Confirm continuous RTSP operation, correct shutter/LED states, bounded
  temporary storage, and acceptable CPU/RAM use during sustained streaming.
- Test capture/measurement timeouts, `rkipc` restarts, application restarts,
  and shutdown.
  Reconnect to the socket after service recovery and avoid switching hardware
  based on missing or stale measurements.
- Measure resources with the camera and RTSP active. The earlier idle-device
  memory reading does not establish the available processing headroom during
  streaming; no camera was connected during that inspection.
