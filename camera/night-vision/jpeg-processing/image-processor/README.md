# JPEG image processor

This application asks the running RKIPC service at `/var/tmp/rkipc` to capture
a snapshot, waits for the JPEG in `/userdata/video0`, and decodes it using the
vendored TJpgDec source in [`tjpgd3/`](tjpgd3/).

It decodes at 1/8 scale and prints JSON containing source and sample
dimensions, mean luma, p10/p50/p90 luma, and minimum and maximum luma. It
removes the processed JPEG by default; `--keep-snapshots` preserves it. The
usage output lists path and sampling interval options.

For each decoded RGB pixel, the processor estimates luma (the pixel's
brightness-like value) with the BT.601 weights:

```text
Y = 0.299 * red + 0.587 * green + 0.114 * blue
```

The implementation uses integer arithmetic for this formula. `mean_y` is the
average of the luma values for all sampled pixels; p10/p50/p90 are luma
percentiles. These are values from the processed JPEG, not physical light
measurements such as lux, and can change with the camera's exposure and image
processing.

The repository-root `./build.sh` stages this app under the SDK's
`project/app/a-eye-night-vision-jpeg/` directory. The SDK builds it with the
selected Rockchip toolchain and includes it in the image as
`/usr/bin/night-vision-jpeg`. The sibling
[`../night-vision-service/`](../night-vision-service/) invokes it for each
brightness sample and controls the shutter and IR LED.

Build standalone with the SDK ARM/uClibc toolchain:

```sh
make -C camera/night-vision/jpeg-processing/image-processor
```

The executable is written to
`camera/night-vision/jpeg-processing/image-processor/build/night-vision-jpeg`.
Override `SDK_ROOT`, `TOOLCHAIN_DIR`, or `CROSS_COMPILE` for a separately
installed toolchain. Clean generated files with:

```sh
make -C camera/night-vision/jpeg-processing/image-processor clean
```

To run it on the device, RKIPC must be running and JPEG snapshots enabled in
its INI:

```sh
adb push camera/night-vision/jpeg-processing/image-processor/build/night-vision-jpeg /tmp/night-vision-jpeg
adb shell /tmp/night-vision-jpeg
adb shell /tmp/night-vision-jpeg --interval-sec 5
```

The snapshot directory must be mounted and writable by RKIPC. Override it with
`--snapshot-dir PATH` if the active INI uses a different location.
