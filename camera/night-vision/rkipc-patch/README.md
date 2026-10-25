# RKIPC measurement patch approach

This is an alternative to [`../jpeg-processing/`](../jpeg-processing/README.md),
not an extension of it. The intended design is to expose brightness or ISP
statistics from inside `rkipc` through its local API. The separate night vision
application would consume those measurements without taking or decoding JPEG
snapshots.

The patch has not been implemented yet. Store future SDK changes as focused
patch files in [`patches/`](patches/) and document the SDK revision and build
steps here. Do not keep a second copy of the SDK's `rkipc` source in this
directory. The consumer should provide the shared
[`BrightnessMetrics`](../common/brightness_metrics.h) result type.
