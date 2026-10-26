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

## Automatic night mode — ongoing

**Status: Ongoing.** Compare the snapshot and `rkipc` patch options below before
choosing the measurement source. Implementation and camera-connected
validation remain to be done.

Create a small C++ application for the Pico Mini that obtains brightness
measurements and controls the night-mode shutter and infrared LEDs. Keep the
existing `rkipc` camera ownership and RTSP stream. The measurement source can
be JPEG snapshots requested through the existing API, or statistics exposed by
a small `rkipc` patch. OpenCV is not required for either approach.

### 1. Compare measurement and decoding options

#### Option A: Request JPEG snapshots through the existing API

Keep `rkipc` unchanged where its existing snapshot and storage behavior is
sufficient. The separate application requests a JPEG, waits for capture to
complete, decodes it, and calculates average grayscale brightness.

Candidate decoders, available as source for cross compilation with the SDK's
ARM/uClibc toolchain:

| Decoder | Integration and memory approach | Tradeoffs |
| --- | --- | --- |
| [TJpgDec](https://elm-chan.org/fsw/tjpgd/) | Small C module, grayscale block callbacks, a few KiB of decoder working memory, and scaling down to 1/8 | First candidate for minimum footprint; baseline JPEG only. Sum pixels in callbacks without storing a full image. |
| [picojpeg](https://github.com/richgel999/picojpeg) | One C source and header, approximately 2.3 KiB working memory, block decoding, no dynamic allocation, and 1/8 reduction mode | Baseline JPEG only; slower decoding and global state make it less convenient for concurrent use. |
| [stb_image](https://github.com/nothings/stb/blob/master/stb_image.h) | Single header with JPEG-only compilation and grayscale output | Simple integration and progressive JPEG support, but allocates the full decoded output plus internal buffers. A 1280x720 grayscale output alone takes 900 KiB. |
| [libjpeg-turbo](https://github.com/libjpeg-turbo/libjpeg-turbo) | C library with grayscale, scanline decoding, scaled decompression, and ARM optimizations | More build integration and a larger library; useful if decoding speed or broader JPEG support justifies it. |

- Confirm the actual hardware-produced JPEG format before selecting a
  baseline-only decoder. Cross-compilation and compatibility with a captured
  snapshot have not yet been validated.
- For TJpgDec, evaluate 1/8 grayscale decoding: a 1280x720 snapshot becomes
  160x90 for analysis. Accumulate pixel sum and count in the output callback,
  then discard each block. No complete decoded image is needed.
- Treat published decoder working-memory figures as excluding application
  memory, stack, and any additional buffers. Measure the final executable
  size, peak RAM, and processing time while RTSP is active.

#### Option B: Patch `rkipc` to expose measurements

Keep the mode decisions and GPIO/PWM control in the separate C++ application.
Add a small measurement API to `rkipc`, accessed through its local socket, so
the application does not need JPEG snapshots or a decoder.

- First investigate the existing AIQ context owned by `rkipc`. The SDK API
  `rk_aiq_user_api2_ae_queryExpResInfo()` provides mean luminance, exposure
  settings, and exposure-limit information. Expose the required values with
  sample freshness/validity information; do not create a second ISP owner.
- Validate which statistics are meaningful for this sensor and IQ profile.
  ISP mean luminance need not match the mean of the final JPEG. Exposure time
  and gain may provide a better indication of darkness than compensated
  image brightness alone.
- If image-derived measurements are needed instead, evaluate a small raw
  NV12 frame consumer inside `rkipc` and calculate brightness from the Y
  plane. Configure the channel and queue depth explicitly, respect stride,
  and release frames promptly. Extra capture buffers must fit the Pico Mini.
- Keep socket requests bounded and avoid blocking the camera/encoder threads.
  Return an unavailable/stale result when the pipeline has no valid sample.
- Account for the maintenance cost: track the SDK source patch and make its
  application, rebuild, and deployment reproducible in this repository.

##### Code-level design for option B

This is a proposed design, pending selection of option B. The SDK has not been
patched for this feature. Paths below are relative to
`sdk/luckfox-pico/project/app/rkipc/rkipc/` unless stated otherwise.

1. **Add the measurement getter in `common/isp/rv1106/isp.c` and declare it
   in the adjacent `isp.h`.** The current `src/rv1103_ipc/CMakeLists.txt`
   compiles this ISP directory. Add
   `rk_isp_get_light_measurement(int cam_id, struct rk_light_measurement *out)`
   using the existing AIQ context and
   `rk_aiq_user_api2_ae_queryExpResInfo()`. Initially support camera 0 in
   normal, non-HDR mode and return explicit errors for unsupported modes or
   unavailable measurements.

   | Measurement | SDK field in `Uapi_ExpQueryInfo_t` |
   | --- | --- |
   | Mean luminance | `LinAeInfo.MeanLuma` |
   | Exposure time | `LinAeInfo.LinearExp.integration_time` |
   | Analog gain | `LinAeInfo.LinearExp.analog_gain` |
   | Digital gain | `LinAeInfo.LinearExp.digital_gain` |
   | ISP digital gain | `LinAeInfo.LinearExp.isp_dgain` |
   | Exposure converged | `IsConverged` |
   | Exposure limit reached | `IsExpMax` |

   Check API return values, output pointers, camera IDs including negative
   IDs, and finite/range-valid values. Document units and calibrate thresholds
   against the sensor/IQ profile; the ISP statistic is not necessarily the
   arithmetic mean of the displayed image.

2. **Synchronize queries with ISP initialization and destruction.** Socket
   handlers run in separate threads, and `rk_isp_set_hdr()` can call
   `rk_isp_deinit()` and `rk_isp_init()` while the process remains running.
   Add a mutex shared by the new getter and the context lifecycle, plus a
   running-state flag. Publish availability only after a successful start,
   invalidate it before teardown, and prevent queries from using a destroyed
   context. Cover failure/early-return paths and release the lock before any
   socket I/O. Use a consistent locking scheme that avoids nested locking
   through the existing initialization helpers.

3. **Add one socket command in `common/socket_server/server.c`.** Implement
   `ser_rk_isp_get_light_measurement(int fd)` and register
   `rk_isp_get_light_measurement` in the existing function map. Read the camera
   ID, invoke the getter, and send the measurements and operation status using
   the existing `/var/tmp/rkipc` protocol, including its final dispatcher
   acknowledgement. Define a compact versioned response and serialize fields
   explicitly rather than sending the vendor structure or relying on compiler
   padding. Check complete reads/writes and bound client-side waits.

4. **Establish measurement freshness.** The exposure-query result has no frame
   ID. A query timestamp records when the API was called, not when a new frame
   arrived. Evaluate the nonblocking
   `rk_aiq_uapi2_sysctl_get3AStats()` API and its statistics `frame_id` to detect
   lack of frame advancement. Verify availability and memory cost on the
   installed firmware. Exposure and statistics queries are separate calls, so
   do not claim exact frame correspondence between their results. Define
   handling for startup, frame-counter reset/wrap, ISP reinitialization, and
   stale results. Identical brightness values alone are not evidence of a
   stalled camera.

5. **Build a diagnostic C++ client first.** Adapt the SDK socket-client pattern
   to request the new command roughly once per second and print luminance,
   exposure, gains, validity, and freshness information. Keep mode decisions
   and GPIO/PWM control in this application. An on-demand statistics query
   needs no additional periodic sampling thread or full image buffer in
   `rkipc`. Validate query latency and concurrent RTSP behavior before adding
   automated transitions.

6. **Integrate the SDK patch reproducibly.** Track the patch in this repository
   and arrange its application and rebuild through the project workflow.
   The RV1103 target already compiles the ISP and socket-server sources and
   links `rkaiq` and `pthread`; edits confined to these existing sources and
   headers should require no new library or CMake source-list entry. Rebuild
   and deploy `/oem/usr/bin/rkipc` as well as the new client. Validate the
   rebuilt binary against the installed vendor libraries, retain a rollback
   binary for development, and test service recovery and ISP reinitialization.

Follow-up investigation: explain why the RV1103 target selects
`common/isp/rv1106` in its CMake configuration. Trace the SDK's shared ISP code
and hardware/library selection before deciding whether this is an issue;
the directory name alone does not establish a device mismatch.

Choose between A and B based on measured resources, the reliability of the
brightness decision, storage requirements, and the cost of maintaining a
vendor application patch. Do not implement both paths by default.

### 2. Validate the existing RKIPC snapshot API if selecting option A

- Follow the SDK's client implementation in
  `project/app/ipcweb/ipcweb-backend/src/socket_client/client.cpp` and its
  socket helpers. Reuse or adapt only the required communication code in the
  new application; the complete web backend is not needed.
- Connect to the Unix socket `/var/tmp/rkipc` and request `rk_take_photo`.
  Preserve the server's capture status: the supplied client wrapper currently
  overwrites it with the result of `cli_end()`.
- With the camera attached, verify that the installed `rkipc` exposes this
  API, JPEG capture succeeds, and RTSP continues during capture. The current
  INI already sets `video.source:enable_jpeg = 1`.
- Verify the storage prerequisite. The RV1103 implementation rejects a
  snapshot unless its storage subsystem reports `DISK_MOUNTED`. With the
  current INI, snapshots are timestamped JPEGs under `/userdata/video0/`.
- Choose a supported temporary destination in RAM for repeated monitoring,
  checking that it satisfies the storage subsystem. Avoid accumulating files
  or repeatedly writing snapshots to flash. Establish whether configuration
  alone is sufficient before considering a change to `rkipc`.
- Handle asynchronous completion: the API returns a request status, not image
  bytes, a filename, or a completed-file notification. Detect the new image
  and confirm it is complete before decoding; use a timeout and handle failed
  captures without changing night-mode state.

### 3. Implement measurement processing and mode decisions

- Cross-compile the application with the SDK's ARM/uClibc toolchain. For
  option A, add the selected JPEG decoder and calculate average grayscale
  luminance, using block/scanline processing where supported. For option B,
  consume the measurements exposed by the patched `rkipc`.
- The init script reads `/etc/default/a-eye-night-vision` and passes the
  thresholds, interval, and consecutive-sample requirement to the controller.
  Current settings enter night below mean luma 80 and return to day above 85
  only when `p90_y` is in 120..135. The default sample interval is 2 seconds,
  and `SWITCH_SAMPLES_REQUIRED=2` requires two consecutive qualifying samples
  for a transition.
  Earlier supplied SC3336 samples were 114.648 in normal light and 93.153 in
  the dark condition.
- Use separate thresholds for entering and leaving night mode, require
  sustained conditions through the configurable consecutive-sample count, and
  allow the image to settle after a mode change.
- Record observed minimum and maximum brightness for diagnostics. Do not use
  lifetime extrema as the sole calibration for switching thresholds.
- Evaluate auto-exposure compensation: mean brightness can stay similar as
  exposure time and gain rise in darkness. Test whether image brightness is
  sufficient. If it is not, evaluate exposure/gain information through option
  B before committing to an image-only decision algorithm.
- Account for the infrared LEDs brightening the image. Define how daylight
  return is detected while IR illumination is active, for example through
  controlled IR-off measurements, to prevent repeated day/night switching.

#### Tune thresholds for borderline indoor/night lighting

**Status: Ongoing.**

- Keep usable normal-mode video in dim indoor conditions without mode
  oscillation. Two consecutive qualifying samples are now required, with a
  default 2-second interval; the user reports the behavior looks better.
  Continue checking that startup/transient samples do not cause unwanted
  transitions.
- Current thresholds are `NIGHT_ON_THRESHOLD=80`, `DAY_ON_THRESHOLD=85`, and
  `p90_y` acceptance band 120..135.
  One-lamp samples were mean 87.4..88.0 / p90 127..128; settled IR-lit night
  samples were mean 86.9..87.4 / p90 143..144. Reflective-object samples had
  p90 248. Verify that these thresholds stop the observed cycling while still
  switching to night in genuinely dark conditions.

### 4. Integrate shutter and infrared LED control — implemented, validate

- `S99a-eye-night-vision` supervises the compiled `/usr/bin/night-vision`
  controller on both camera builds. It reads `mean_y` from the JPEG app every
  2 seconds by default using values from `/etc/default/a-eye-night-vision`, and
  uses half
  of the PWM LED's reported maximum brightness in
  night mode. On IMX415 it also drives the active-low GPIO3_C4 / GPIO116 low
  for night and high for day; on SC3336 it leaves that reference-clock pin
  untouched. Verify shutter state and mode transitions on the device.
- The controller supports two compile-time grayscale backends selected by
  `RKIPC_NIGHT_MODE`: `1` (default) uses RKIPC's `rk_isp_set_night_to_day()`
  AIE black-and-white mode; `0` uses the RKIPC saturation setter and
  saves/restores the original value. The tracked
  IMX415 INI omits IR-cut GPIO settings so the controller retains direct control
  of GPIO116 and the IR LED. Revisit the SDK API status handling if this backend
  is selected for production.
- Keep `test-pwm-led.sh` installed for manual checks; the init service does not
  run it. On SC3336 the night-vision controller changes the LED only and leaves
  PC4 untouched because it is used on that camera's reference-clock path.
- Validate that omitting stock IR-cut GPIO settings lets the RKIPC
  night-to-day API select black-and-white without operating unrelated pins.
- The root build script stages the JPEG image processor, C++ night-vision
  service, and init service into the image. Validate the integration with a
  full build and camera-connected run.

### 5. Validate on the Pico Mini

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
