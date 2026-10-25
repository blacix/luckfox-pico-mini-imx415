# Night-vision service

`night-vision.cpp` is the long-running controller for the JPEG image processor
in [`../image-processor/`](../image-processor/README.md). Every 5 seconds by
default, it reads the processor's `mean_y` JSON value and applies hysteresis.
The init script reads thresholds and sample interval from
`/etc/default/a-eye-night-vision` and passes them to the executable as
command-line options; the C++ program does not read the file itself. The
tracked source config currently enters night mode below 90 and returns to day
mode above 100. On IMX415, night mode
sets GPIO116 high and day mode sets it low. On SC3336, GPIO116 is left untouched
because it carries the camera reference clock. Both camera modes drive the PWM
IR LED at half its reported maximum brightness at night and turn it off by day.

On night-mode entry, it also uses RKIPC's local socket API to set ISP saturation
to zero, making the existing RTSP stream grayscale. It reads and saves the
current saturation first, restores it on day-mode entry and shutdown, and keeps
the saved value in `/run` so it can recover if the controller restarts while
night mode is active. If RKIPC's socket is unavailable, LED and shutter control
continue and saturation changes are retried on later samples.

The program accepts `--night-on`, `--day-on`, and `--interval-sec`. When
launched through the init script, it receives values from
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

The executable is written to
`camera/night-vision/jpeg-processing/night-vision-service/build/night-vision`.
The repository-root `./build.sh` stages it as an SDK app package and includes
it and its `rkipc_saturation.cpp` helper in the firmware image.
`S99a-eye-night-vision` starts and supervises the installed executable on both
camera builds. On SC3336 it uses LED-only mode and does not touch GPIO116.
