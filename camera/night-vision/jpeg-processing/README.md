# JPEG snapshot processing

This is the snapshot-based measurement approach. It sends `rk_take_photo` to
the running RKIPC service at `/var/tmp/rkipc`, waits for the resulting JPEG in
`/userdata/video0`, and decodes it with the vendored TJpgDec source in
[`tjpgd3/`](tjpgd3/).

The application decodes at 1/8 scale and prints one JSON object containing the
source and sample dimensions, mean luma, p10/p50/p90 luma, and minimum and
maximum luma. It removes the processed JPEG by default; `--keep-snapshots`
preserves it. The usage output lists the path and sampling interval options.

Cross-compile from the repository root with the SDK toolchain:

```sh
TOOLCHAIN=sdk/luckfox-pico/tools/linux/toolchain/arm-rockchip830-linux-uclibcgnueabihf/bin
"$TOOLCHAIN/arm-rockchip830-linux-uclibcgnueabihf-gcc" \
  -std=c99 -O2 -Wall -Wextra \
  -Icamera/night-vision/jpeg-processing/tjpgd3/src \
  -c camera/night-vision/jpeg-processing/tjpgd3/src/tjpgd.c \
  -o /tmp/tjpgd.o
"$TOOLCHAIN/arm-rockchip830-linux-uclibcgnueabihf-g++" \
  -std=c++11 -O2 -Wall -Wextra \
  -Icamera/night-vision/jpeg-processing/tjpgd3/src \
  -Icamera/night-vision/common \
  camera/night-vision/jpeg-processing/main.cpp /tmp/tjpgd.o \
  -pthread -o camera/night-vision/jpeg-processing/night-vision-jpeg
```

Run on the device while RKIPC is running and JPEG snapshots are enabled in its
configuration:

```sh
./night-vision-jpeg
./night-vision-jpeg --interval-sec 5
```

The snapshot directory must be mounted and writable by RKIPC. Override it with
`--snapshot-dir PATH` if the active INI uses a different location. Hardware
capture and brightness results still need validation with the camera attached.
