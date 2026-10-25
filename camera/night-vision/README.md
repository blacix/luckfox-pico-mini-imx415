# Night vision

The project has two approaches to obtain brightness measurements while
keeping `rkipc` as the camera owner:

- [`jpeg-processing/`](jpeg-processing/README.md) asks the existing `rkipc`
  service for a JPEG snapshot. Its `image-processor/` decodes the frame with
  TJpgDec and calculates luma statistics; `night-vision-service/` uses those
  measurements to control the shutter and IR LED.
- [`rkipc-patch/`](rkipc-patch/README.md) is an alternative approach that
  exposes measurements from inside a patched `rkipc`. It does not use the JPEG
  snapshot or TJpgDec path.

The image-processing approach uses the shared brightness metric in
[`common/brightness_metrics.h`](common/brightness_metrics.h). The repository
root `./build.sh` stages the image processor and service as separate SDK app
packages and includes both executables in the firmware image.

Keep vendor source changes as patch files under `rkipc-patch/patches/` rather
than copying the SDK's `rkipc` sources into this directory.
