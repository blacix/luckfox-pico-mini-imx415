# Night-vision service

`night-vision.cpp` is the long-running controller for the JPEG image processor
in [`../image-processor/`](../image-processor/README.md). Every 2 seconds by
default, it reads the processor's `mean_y` and `p90_y` JSON values and applies
hysteresis.
The init script reads thresholds, sample interval, and required consecutive
sample count from
`/etc/default/a-eye-night-vision` and passes them to the executable as
command-line options; the C++ program does not read the file itself. The
tracked source config currently enters night mode below `mean_y` 70. It returns
to day only when `mean_y` is above 90 and `p90_y` is in the inclusive 105..180
acceptance band. These are trial settings to validate across lighting and
exposure conditions. Near-saturated reflective-object samples measured at p90
248 remain outside the band. On IMX415, the
shutter input is active-low: night mode sets
GPIO116 low and day mode sets it high. On SC3336, GPIO116 is left untouched
because it carries the camera reference clock. Both camera modes drive the PWM
IR LED at half its reported maximum brightness at night and turn it off by day.

The grayscale backend is selected at compile time with `RKIPC_NIGHT_MODE`:

- `1` (default) calls `rk_isp_set_night_to_day("night"/"day")`, selecting the
  RV1106 ISP's AIE black-and-white effect. The tracked IMX415 INI omits the
  IR-cut GPIO settings, so the service remains responsible for GPIO116 and the
  IR LED. This SDK function returns an unreliable status; the service checks
  socket delivery but cannot confirm the API's internal result.
- `0` sets ISP saturation to zero through RKIPC. It saves the existing
  setting, restores it in day mode and shutdown, and stores the saved value in
  `/run` for recovery after a service restart.

If RKIPC's socket is unavailable, LED and shutter control continue and the
selected image-mode request is retried on later samples.

The program accepts `--night-on`, `--day-on`, `--day-p90-min`, `--day-p90-max`,
`--interval-sec`, and `--samples-required`. A transition requires two
consecutive qualifying samples by default (`SWITCH_SAMPLES_REQUIRED=2` in the
tracked config); a nonqualifying or invalid sample resets the corresponding
count. When launched through the init script, it receives values from
`/etc/default/a-eye-night-vision`; direct launches need the options on the
command line. It logs status and
errors to `/tmp/night-vision.log`,
truncating that file at startup. When `/etc/init.d/S99a-eye-cam` is absent, it
does not configure or write GPIO116; it still samples brightness and controls
the IR LED. This keeps GPIO3_C4 untouched on SC3336, where it carries the
camera reference clock.

Build standalone with the SDK ARM/uClibc toolchain:

```sh
make -C camera/night-vision/jpeg-processing/night-vision-service
```

With the default `RKIPC_NIGHT_MODE=1`, the executable is written to
`camera/night-vision/jpeg-processing/night-vision-service/build/1/night-vision`.
Select the saturation fallback at compile time with:

```sh
make -C camera/night-vision/jpeg-processing/night-vision-service \
	RKIPC_NIGHT_MODE=0
```

Its executable is written under `build/0/`.
The repository-root `./build.sh` stages it as an SDK app package and includes
it and the `rkipc_isp.cpp` helper in the firmware image. Use
`RKIPC_NIGHT_MODE=0 ./build.sh imx415` to build a full image with the saturation
fallback.
`S99a-eye-night-vision` starts and supervises the installed executable on both
camera builds. On SC3336 it uses LED-only mode and does not touch GPIO116.
