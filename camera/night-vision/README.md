# Night vision

The project is evaluating two separate ways to obtain brightness measurements
while keeping `rkipc` as the camera owner:

- [`jpeg-processing/`](jpeg-processing/README.md) asks the existing `rkipc`
  service for a JPEG snapshot, decodes it with TJpgDec, and calculates image
  luma statistics.
- [`rkipc-patch/`](rkipc-patch/README.md) is an alternative approach that
  exposes measurements from inside a patched `rkipc`. It does not use the JPEG
  snapshot or TJpgDec path.

Both approaches should report the shared result type in
[`common/brightness_metrics.h`](common/brightness_metrics.h). The night mode
thresholds, hysteresis, shutter control, and IR LED control are not implemented
here yet.

Keep vendor source changes as patch files under `rkipc-patch/patches/` rather
than copying the SDK's `rkipc` sources into this directory.
