# Night-vision service

`night-vision.cpp` is the long-running controller for the JPEG image processor
in [`../image-processor/`](../image-processor/README.md). Every 10 seconds by
default, it reads the processor's `mean_y` JSON value and applies hysteresis:
night mode below 100, day mode above 110. These thresholds separate the
provided normal-light mean (114.648) and dark-condition mean (93.153), with a
10-point hysteresis gap. It sets GPIO116 high for night and
drives the PWM IR LED at half its reported maximum brightness. Day mode sets
GPIO116 low and turns the LED off.

The defaults were calibrated from the supplied SC3336 samples: normal-light
mean 114.648 and dark-condition mean 93.153. The program accepts `--night-on`,
`--day-on`, and `--interval-sec`. The init script currently launches it with
its built-in defaults. It logs status and errors to `/tmp/night-vision.log`,
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
it in the firmware image. `S99a-eye-night-vision` starts and supervises the
installed executable on IMX415 builds.
