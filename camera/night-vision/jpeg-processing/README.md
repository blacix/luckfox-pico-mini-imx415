# JPEG snapshot processing

This is the snapshot-based measurement approach. It sends `rk_take_photo` to
the running RKIPC service at `/var/tmp/rkipc`, waits for the resulting JPEG in
`/userdata/video0`, and decodes it with the vendored TJpgDec source in
[`tjpgd3/`](tjpgd3/).

The application decodes at 1/8 scale and prints one JSON object containing the
source and sample dimensions, mean luma, p10/p50/p90 luma, and minimum and
maximum luma. It removes the processed JPEG by default; `--keep-snapshots`
preserves it. The usage output lists the path and sampling interval options.

The repository-root `./build.sh` stages this source and Makefile under the
SDK's `project/app/a-eye-night-vision-jpeg/` directory before the SDK build.
The SDK then builds it with the other application packages and includes it in
the image as `/usr/bin/night-vision-jpeg`. It is not started automatically.

Build it standalone with the SDK's ARM/uClibc toolchain:

```sh
make -C camera/night-vision/jpeg-processing
```

The executable is written to `camera/night-vision/jpeg-processing/build/`.
Override `SDK_ROOT`, `TOOLCHAIN_DIR`, or `CROSS_COMPILE` when using a separately
installed SDK toolchain. Clean the generated files with:

```sh
make -C camera/night-vision/jpeg-processing clean
```

Copy the resulting executable to the device to run it while RKIPC is running
and JPEG snapshots are enabled in its configuration:

```sh
adb push camera/night-vision/jpeg-processing/build/night-vision-jpeg /tmp/night-vision-jpeg
adb shell /tmp/night-vision-jpeg
adb shell /tmp/night-vision-jpeg --interval-sec 5
```

The snapshot directory must be mounted and writable by RKIPC. Override it with
`--snapshot-dir PATH` if the active INI uses a different location. Hardware
capture and brightness results still need validation with the camera attached.
