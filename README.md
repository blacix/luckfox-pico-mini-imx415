# LuckFox Pico Mini SC3336 and IMX415 Camera Support

This repository contains the work required to build firmware for a LuckFox Pico
Mini board based on the Rockchip RV1103G SoC with either its supported SC3336
camera or a Sony IMX415 camera.

The project covers the kernel sensor driver, device-tree configuration,
Rockchip camera-pipeline integration, firmware changes, camera tuning files,
and the validation needed to capture frames from the board.

## Target hardware

- Board: LuckFox Pico Mini
- SoC: Rockchip RV1103G
- Kernel: Linux 5.10.160
- Operating system: Buildroot 2023.02.6
- Camera: SC3336 or Sony IMX415, selected at build time
- Camera interface: two-lane MIPI CSI-2

The IMX415 configuration uses a two-lane binned 1944x1097 sensor mode, cropped
to 1920x1080 by the camera pipeline and scaled to 1280x720 by `rkipc`. The
remaining work is end-to-end validation on the Pico Mini.

## Repository structure

```text
.
├── README.md
├── camera.md
├── build.sh                       # Synchronizes project inputs and builds firmware
├── deploy.sh                      # Deploys selected changes to a running device
├── camera/                       # Tracked IMX415 camera configuration
│   ├── imx415_CMK-OT2022-PX1_IR0147-36IRC-8M-F20.json
│   ├── imx415.c                   # Tracked IMX415 kernel driver source
│   ├── rkipc-imx415-720p.ini
│   └── night-vision/              # Brightness measurement and mode control apps
│       ├── common/
│       ├── jpeg-processing/
│       │   ├── image-processor/   # Snapshot capture, JPEG decoding, metrics
│       │   │   ├── main.cpp
│       │   │   ├── Makefile
│       │   │   └── tjpgd3/
│       │   └── night-vision-service/
│       │       ├── night-vision.cpp
│       │       └── Makefile
│       └── rkipc-patch/
├── implementation-plan.md
├── kernel/                       # Tracked kernel inputs
│   ├── rv1103-luckfox-pico-ipc.dtsi
│   └── luckfox_rv1106_linux_defconfig
├── overlay/                     # Tracked rootfs overlay inputs
│   └── a-eye/
│       ├── etc/init.d/S99a-eye-night-vision
│       ├── etc/init.d/S99a-eye-cam
│       └── usr/bin/
│           ├── rkipc-supervisor.sh
│           ├── night-vision.sh       # Optional shell controller for manual use
│           └── test-pwm-led.sh
└── sdk/                         # Local SDK and firmware tools; ignored by Git
    ├── Luckfox_Pico_Mini_Flash_250607/
    │   └── Stock firmware images and update files
    ├── luckfox-pico/
    │   └── LuckFox Pico SDK source tree
    ├── upgrade_tool -> upgrade_tool_v2_17/
    └── upgrade_tool_v2_17/
        └── Downloaded firmware upgrade utility and supporting files
```

### Documentation

- `camera.md` records the current board state, camera pipeline findings,
  installed drivers, firmware contents, and hardware compatibility questions.
- `implementation-plan.md` lists the remaining camera-selection and 1080p
  validation work.

### `sdk/`

The `sdk/` directory is a local working area for the large files needed to
build and flash the board. It currently contains:

- the LuckFox Pico SDK source tree;
- the stock LuckFox Pico Mini firmware image set used for rollback and
  comparison;
- the LuckFox firmware upgrade tool.

The directory is intentionally ignored in the root `.gitignore` because it is
large and contains vendor tools and firmware artifacts. A fresh checkout must
therefore be supplied with the required SDK and firmware files separately.

### Install the upgrade tool

Download the LuckFox/Rockchip upgrade-tool package and extract it inside
`sdk/`. The README commands use the unversioned path `sdk/upgrade_tool/`.
Either create a link from that name to the extracted versioned directory:

```sh
ln -sr sdk/upgrade_tool_v2_17 sdk/upgrade_tool
```

Run this from the repository root. `-r` makes the link target relative to
`sdk/upgrade_tool`, so the `sdk/...` source and destination paths work as
written. Replace `upgrade_tool_v2_17` with the directory name produced by your
download.
Alternatively, move or extract the package directory itself to
`sdk/upgrade_tool/` instead of creating a link. The tool is not installed on
`PATH`.

### Flashing the stock image

The stock firmware image is located at:

```text
sdk/Luckfox_Pico_Mini_Flash_250607/update.img
```

From the repository root, run:

```sh
./sdk/upgrade_tool/upgrade_tool uf \
  ./sdk/Luckfox_Pico_Mini_Flash_250607/update.img
```

The board should be recoverable to this stock image before experimental
firmware changes are flashed.

## Development objective

The project has a full-image build path for either camera. The IMX415 build uses
the project camera service, INI, and IQ file; the SC3336 build uses the SDK's
stock camera startup and IQ configuration. Outstanding target checks are
listed in [implementation-plan.md](implementation-plan.md). The stock SC3336 IQ
file is not an IMX415 configuration.

## Tracked project files and SDK synchronization

The project maintains modified kernel inputs under `kernel/`, the IMX415
driver and camera files under `camera/`, and rootfs additions under `overlay/`.
The SDK directory is ignored by this repository. Before the first build
overwrites SDK files with tracked project files, save the original DTSI,
IMX415 driver, and kernel defconfig as `.orig`. The build script also edits the
SDK board DTS in place to enable GMAC; save its original copy as well. Run this
once from the repository root:

```sh
cp sdk/luckfox-pico/sysdrv/source/kernel/arch/arm/boot/dts/rv1103-luckfox-pico-ipc.dtsi \
  sdk/luckfox-pico/sysdrv/source/kernel/arch/arm/boot/dts/rv1103-luckfox-pico-ipc.dtsi.orig
cp sdk/luckfox-pico/sysdrv/source/kernel/arch/arm/boot/dts/rv1103g-luckfox-pico-mini.dts \
  sdk/luckfox-pico/sysdrv/source/kernel/arch/arm/boot/dts/rv1103g-luckfox-pico-mini.dts.orig
cp sdk/luckfox-pico/sysdrv/source/kernel/drivers/media/i2c/imx415.c \
  sdk/luckfox-pico/sysdrv/source/kernel/drivers/media/i2c/imx415.c.orig
cp sdk/luckfox-pico/sysdrv/source/kernel/arch/arm/configs/luckfox_rv1106_linux_defconfig \
  sdk/luckfox-pico/sysdrv/source/kernel/arch/arm/configs/luckfox_rv1106_linux_defconfig.orig
```

The tracked project files copied into the SDK are:

| Tracked project file | SDK destination |
| --- | --- |
| `kernel/rv1103-luckfox-pico-ipc.dtsi` | `sdk/luckfox-pico/sysdrv/source/kernel/arch/arm/boot/dts/rv1103-luckfox-pico-ipc.dtsi` |
| `kernel/luckfox_rv1106_linux_defconfig` | `sdk/luckfox-pico/sysdrv/source/kernel/arch/arm/configs/luckfox_rv1106_linux_defconfig` |
| `camera/imx415.c` | `sdk/luckfox-pico/sysdrv/source/kernel/drivers/media/i2c/imx415.c` |
| `overlay/a-eye/etc/init.d/S99a-eye-night-vision` | `sdk/luckfox-pico/project/cfg/BoardConfig_IPC/overlay/overlay-luckfox-buildroot-init/etc/init.d/S99a-eye-night-vision` (all builds) |
| `overlay/a-eye/usr/bin/test-pwm-led.sh` | `sdk/luckfox-pico/project/cfg/BoardConfig_IPC/overlay/overlay-luckfox-buildroot-init/usr/bin/test-pwm-led.sh` (all builds) |
| `overlay/a-eye/usr/bin/night-vision.sh` | `sdk/luckfox-pico/project/cfg/BoardConfig_IPC/overlay/overlay-luckfox-buildroot-init/usr/bin/night-vision.sh` (all builds; optional manual controller) |
| `overlay/a-eye/etc/init.d/S99a-eye-cam` | `sdk/luckfox-pico/project/cfg/BoardConfig_IPC/overlay/overlay-luckfox-buildroot-init/etc/init.d/S99a-eye-cam` (IMX415 only) |
| `overlay/a-eye/usr/bin/rkipc-supervisor.sh` | `sdk/luckfox-pico/project/cfg/BoardConfig_IPC/overlay/overlay-luckfox-buildroot-init/usr/bin/rkipc-supervisor.sh` (IMX415 only) |
| `camera/rkipc-imx415-720p.ini` | `sdk/luckfox-pico/project/cfg/BoardConfig_IPC/overlay/overlay-luckfox-buildroot-init/usr/share/rkipc-imx415-720p.ini` (IMX415 only) |
| `camera/imx415_CMK-OT2022-PX1_IR0147-36IRC-8M-F20.json` | `sdk/luckfox-pico/project/cfg/BoardConfig_IPC/overlay/overlay-luckfox-buildroot-init/usr/share/iqfiles/imx415_CMK-OT2022-PX1_IR0147-36IRC-8M-F20.json` (IMX415 only) |
| `camera/night-vision/jpeg-processing/image-processor/` and shared `brightness_metrics.h` | `sdk/luckfox-pico/project/app/a-eye-night-vision-jpeg/` (staged and built for all camera selections) |
| `camera/night-vision/jpeg-processing/night-vision-service/` | `sdk/luckfox-pico/project/app/a-eye-night-vision-service/` (staged and built for all camera selections) |

`build.sh` is the tracked build entry point; it is not an SDK configuration
file. In addition to copying the files above, it changes
`&gmac` from `disabled` to `okay` in the SDK's
`rv1103g-luckfox-pico-mini.dts`. The board DTS is therefore edited in place,
not replaced by a tracked project file. The script clears existing
`/etc/init.d/S99a-eye*` services and the known IMX415 camera files from the SDK
overlay before installing the files for the selected camera. Both builds get
`S99a-eye-night-vision` and `test-pwm-led.sh`. The init service does not call
the LED tester; it starts the compiled `/usr/bin/night-vision` app only for the
IMX415 build, where GPIO3_C4 is the shutter line. IMX415 builds also include
`night-vision.sh` as an optional manual alternative; do not run it alongside
the C++ service. On SC3336 the service still switches the PWM LED, but leaves
GPIO3_C4 untouched because it carries the camera reference clock. Only an IMX415
build gets `S99a-eye-cam`, `rkipc-supervisor.sh`, the IMX415 INI, and its IQ JSON. An
SC3336 build therefore leaves the SDK's stock camera configuration and IQ
files in place without installing the IMX415 camera service or profile.

`camera/rkipc-imx415-720p.ini` is the project-owned 720p IMX415 profile for the
`rkipc` application, adapted from the extracted Pico Zero profile.
`camera/imx415_CMK-OT2022-PX1_IR0147-36IRC-8M-F20.json` is the matching ISP IQ
tuning file. Both are needed for the tested IMX415 `rkipc` setup. For an
IMX415 build, the root `build.sh` copies them into the SDK's selected Buildroot
overlay, so they are included in the image at
`/usr/share/rkipc-imx415-720p.ini` and
`/usr/share/iqfiles/imx415_CMK-OT2022-PX1_IR0147-36IRC-8M-F20.json`. Before
processing either camera selection, the script removes these known project
copies from the SDK overlay; an SC3336 build does not put them back.

Make camera, kernel, and rootfs changes in the tracked files under `kernel/`,
`overlay/`, and `camera/`. Change the root `build.sh` when the SDK
synchronization or build steps need updating. It copies tracked kernel inputs,
driver source, and the files required for the selected camera into the SDK
before building. It stages the JPEG image processor and night-vision service
as separate SDK app packages. The SDK builds them with the selected Rockchip
toolchain and includes `/usr/bin/night-vision-jpeg` (snapshot analysis) and
`/usr/bin/night-vision` (the controller) in the image. The init service starts
the controller on IMX415 builds; the image processor is called by the service.
The stock
Pico Mini BoardConfig already selects the init
overlay, so no custom BoardConfig is needed. The tracked DTSI contains the
SC3336 and IMX415 nodes, the CSI-2 graph, PWM0 LED setup, and enables `&gmac`
for wired Ethernet.
The Pico Mini board DTS later overrides GMAC to disabled, so the root build
script also changes that board-level status to `okay` in the SDK copy. GMAC
uses the SoC-integrated PHY described in `rv1106.dtsi`; SDK startup networking
brings up `eth0` and requests an address with DHCP. The root build script
selects one supported camera in the SDK copy. SC3336 uses D-PHY input 0;
IMX415 uses D-PHY input 3, matching the working RV1103 camera configuration.
The defconfig enables
`CONFIG_VIDEO_SC3336=m`, `CONFIG_VIDEO_IMX415=m`, and `CONFIG_LEDS_PWM=y`.

## Building, flashing, and testing the image

The root build script builds and packages the complete firmware image; it is
not a driver-only build. The tracked DTSI configures PWM0 as the LED consumer,
and the tracked kernel defconfig enables PWM LED support and both SC3336 and
IMX415 drivers. Choose the camera attached to the board for each build:

1. Keep camera node definitions in the tracked DTSI and configure the PWM LED
   and kernel options in the tracked project files. The build script enables
   only the selected camera. SC3336 uses D-PHY input 0; IMX415 uses input 3.
2. Select the SPI-NAND LuckFox Pico Mini target only once for this SDK setup:

   ```sh
   ./sdk/luckfox-pico/build.sh lunch
   ```

   Choose `RV1103_Luckfox_Pico_Mini`, `[1] SPI_NAND`, and `Buildroot`.
3. Build the full image from the repository root. IMX415 is the default, so
   `./build.sh` and `./build.sh imx415` select the same camera. Pass `sc3336`
   explicitly for the stock camera. The script selects the camera in its DTSI
   copy, enables GMAC in the Pico Mini board DTS, installs shared LED files,
   and installs the IMX415 service and camera files only for an IMX415 build.
   It stages the JPEG image processor and night-vision service for the SDK app
   build, then builds all components and packages `update.img`:

   ```sh
   ./build.sh
   ./build.sh imx415  # Same camera selection as ./build.sh
   # Or select the stock SC3336 camera:
   ./build.sh sc3336
   ```
4. Flash the generated image to the board:

   ```sh
   ./sdk/upgrade_tool/upgrade_tool uf \
     ./sdk/luckfox-pico/output/image/update.img
   ```
5. After the board boots, test the PWM LED using the section below. Validate
   the selected sensor’s probe, media topology, and frame capture using the steps in
   [implementation-plan.md](implementation-plan.md).

The SDK stores the selected target in `.BoardConfig.mk`; do not run `lunch`
again for subsequent builds. The image includes the SC3336 and IMX415 modules
under `/oem/usr/ko/`, and the SDK startup sequence loads them during boot.
After flashing, verify the selected driver with
`lsmod | grep -E 'sc3336|imx415'`.

Use `deploy.sh` only when a changed module, camera configuration, or service
needs to be tried on the running device without rebuilding and flashing the
complete image. Device-tree, kernel configuration, or SDK build integration
changes still require a full image build and flash.

After the build, locate the generated modules and verify the kernel
configuration:

```sh
ls -l sdk/luckfox-pico/sysdrv/source/objs_kernel/drv_ko/lib/modules/5.10.160/kernel/drivers/media/i2c/{imx415,sc3336}.ko
grep -n "CONFIG_VIDEO_IMX415\|CONFIG_VIDEO_SC3336\|CONFIG_LEDS_PWM" sdk/luckfox-pico/sysdrv/source/objs_kernel/.config
```

The expected configuration is:

```text
CONFIG_VIDEO_IMX415=m
CONFIG_VIDEO_SC3336=m
CONFIG_LEDS_PWM=y
```

## Deploying changes for quick testing

After making a change that can be tested against the currently installed
kernel and device tree, build the kernel module if it changed, connect the
device with root ADB, then run this from the repository root. The script
expects the module artifact to exist even when only a config or script changed;
in that case it redeploys the existing module too.

```sh
./deploy.sh
```

For an IMX415 image, `deploy.sh` pushes the built `imx415.ko` and these
tracked project files to the device:

- `overlay/a-eye/usr/bin/test-pwm-led.sh` to `/usr/bin/test-pwm-led.sh`;
- `overlay/a-eye/usr/bin/night-vision.sh` to `/usr/bin/night-vision.sh` as an
  optional manual alternative to the C++ service;
- `night-vision` and `night-vision-jpeg` from the SDK app build to
  `/usr/bin/night-vision` and `/usr/bin/night-vision-jpeg`;
- `overlay/a-eye/usr/bin/rkipc-supervisor.sh` to
  `/usr/bin/rkipc-supervisor.sh`;
- `overlay/a-eye/etc/init.d/S99a-eye-night-vision` to
  `/etc/init.d/S99a-eye-night-vision`;
- `overlay/a-eye/etc/init.d/S99a-eye-cam` to `/etc/init.d/S99a-eye-cam`;
- `camera/rkipc-imx415-720p.ini` to `/usr/share/rkipc-imx415-720p.ini`;
- the camera IQ JSON to `/usr/share/iqfiles/`;
- `imx415.ko` to `/oem/usr/ko/imx415.ko`.

The script stops the LED and camera services, unloads the currently loaded
IMX415 module if present, installs and loads the new module, then starts the
camera and night-vision services. The camera service launches `rkipc` with the deployed INI and IQ
directory. It also removes the retired `/usr/bin/night-vision.sh`. `deploy.sh`
does not remove old init-service filenames from a
running image; flash a newly built image to apply the service rename cleanly.
Deployment requires a connected device with a root ADB shell and a module
built for the device's currently running kernel.

This is an iteration shortcut, not a replacement for a firmware build. Use it
for changes to the module binary, INI/IQ files, or deployed scripts when the
running kernel and device tree already support the camera. Changes to the
device tree, kernel configuration, or other build-time inputs require
`./build.sh imx415` and flashing the resulting image. If nothing changed and
you are not testing an update, there is no need to run `deploy.sh`.

## USB networking, RTSP streaming, and V4L2 capture

### Set up the host USB Ethernet interface

The board exposes a USB network interface named `usb0`. Check its current
address from the host with:

```sh
adb shell 'ip -4 addr show dev usb0'
```

In the current setup, the device reports `172.32.0.93/16`. Give the host's USB
Ethernet interface a different address in the same subnet. Find its name with
`ip -br link`; it may look like `enx...`. For example:

```sh
sudo ip link set dev enx... up
sudo ip addr replace 172.32.0.100/16 dev enx...
```

Replace `enx...` with the actual host interface name. The host and device
addresses must be unique. Verify that the route to the device uses this USB
interface with `ip route get 172.32.0.93`, then check connectivity with
`ping 172.32.0.93`.

### Use the board's integrated wired Ethernet PHY

The Pico Mini SDK DTS disables `&gmac` by default. The root `build.sh` enables
it in the SDK board DTS for each image build. The SoC DTS already describes
its integrated PHY and RMII mode, so this setup does not add an external PHY
node. The SDK startup code brings up `eth0` and runs DHCP. After boot, check
the wired interface and its address with:

```sh
adb shell 'ip -4 addr show dev eth0'
```

This is separate from the USB `usb0` network interface described above.

### Start `rkipc` with the IMX415 files and view RTSP

The `rkipc` application provides the RTSP server. The main stream is available
at `/live/0` on port 554. The tracked `/etc/init.d/S99a-eye-cam` service stops
the stock `rkipc` process and starts `/usr/bin/rkipc-supervisor.sh`. The
supervisor loads `/oem/usr/ko/imx415.ko` if needed and waits until it binds to
I²C device `4-0037` before launching `/oem/usr/bin/rkipc` with
`/usr/share/rkipc-imx415-720p.ini` (`-c`) and `/usr/share/iqfiles` (`-a`). If
the sensor is not ready, the supervisor retries binding every five seconds and
does not start `rkipc` until binding succeeds. If `rkipc` exits, it retries
after the same delay. In the full image, `S99a-eye-cam` is in the boot init
sequence and launches the supervisor for the IMX415 setup. After deploying
changes with `./deploy.sh`, the service restarts immediately. This
IMX415-specific service should not replace the stock camera process in a
SC3336 setup.

```sh
adb shell /etc/init.d/S99a-eye-cam restart
```

Use the service to stop the camera process or restart it after boot:

```sh
adb shell /etc/init.d/S99a-eye-cam stop
```

The supervisor writes output and restart messages to `/tmp/rkipc.log`, clearing
it before each `rkipc` attempt so only the latest attempt is retained. A single
long-running attempt can still produce a large log. It sets
`LD_LIBRARY_PATH=/oem/usr/lib:/oem/lib` for `rkipc`, so its vendor libraries
are found when it is launched by init without an interactive shell
environment. If startup fails or the service keeps restarting, inspect the
log with `adb shell tail -n 80 /tmp/rkipc.log`.

Check the RTSP port and play the stream from the host:

```sh
nc -vz -w 3 172.32.0.93 554
ffplay -rtsp_transport tcp -fflags nobuffer -flags low_delay \
  -framedrop -analyzeduration 0 -probesize 32 -sync video \
  rtsp://172.32.0.93:554/live/0
```

If using ADB forwarding instead of the USB device IP, forward port 554 and use
the loopback URL:

```sh
adb forward tcp:8554 tcp:554
ffplay -rtsp_transport tcp rtsp://127.0.0.1:8554/live/0
```

The ffplay options reduce client-side buffering; the camera pipeline or RTSP
server may still add latency. To stop and restart the stock application stack:

```sh
adb shell /etc/init.d/S21appinit stop
adb shell /etc/init.d/S21appinit start
```

The stop action terminates `rkipc` and other application init scripts, so the
RTSP stream is unavailable until it starts again. After starting the stock
application stack on an IMX415 build, restart `S99a-eye-cam` to run the custom
IMX415 configuration.

### Read back the SPI-NAND firmware

The Rockchip upgrade tool reads partitions while the board is in Loader mode.
If it is detected as `Maskrom`, load the SDK's generated loader into RAM with
`DB`; this does not write it to flash. From the repository root:

```sh
sudo ./sdk/upgrade_tool/upgrade_tool LD
sudo ./sdk/upgrade_tool/upgrade_tool DB \
  sdk/luckfox-pico/output/image/download.bin
sudo ./sdk/upgrade_tool/upgrade_tool LD
sudo ./sdk/upgrade_tool/upgrade_tool PL
```

`PL` prints the device's parameter partition table. On the current firmware it
reports:

```text
Partition Info(parameter):
NO  LBA        Size       Name
01  0x00000000 0x00000200 env
02  0x00000200 0x00000200 idblock
03  0x00000400 0x00000400 uboot
04  0x00000800 0x00002000 boot
05  0x00002800 0x0000f000 oem
06  0x00011800 0x00003000 userdata
07  0x00014800 0x0002a800 rootfs
```

`RL` reads a range of sectors using `RL <start-LBA> <sector-count> <file>`.
To save each listed partition separately, run these from the repository root:

```sh
sudo ./sdk/upgrade_tool/upgrade_tool RL 0x00000000 0x00000200 env.img
sudo ./sdk/upgrade_tool/upgrade_tool RL 0x00000200 0x00000200 idblock.img
sudo ./sdk/upgrade_tool/upgrade_tool RL 0x00000400 0x00000400 uboot.img
sudo ./sdk/upgrade_tool/upgrade_tool RL 0x00000800 0x00002000 boot.img
sudo ./sdk/upgrade_tool/upgrade_tool RL 0x00002800 0x0000f000 oem.img
sudo ./sdk/upgrade_tool/upgrade_tool RL 0x00011800 0x00003000 userdata.img
sudo ./sdk/upgrade_tool/upgrade_tool RL 0x00014800 0x0002a800 rootfs.img
```

To save the whole listed partition range as one contiguous raw LBA image, read
from LBA 0 for `0x3f000` sectors (the end of `rootfs`):

```sh
sudo ./sdk/upgrade_tool/upgrade_tool RL \
  0x00000000 0x0003f000 spi-nand-partitioned.img
```

The combined file is about 126 MiB and includes all listed partitions. It is a
raw logical-sector image, not a packaged Rockchip `update.img` and not a
physical NAND dump containing spare/OOB data. Use `RFI` to query the chip
capacity if you also need to account for unpartitioned space.

### Capture one frame with `v4l2-ctl`

Stop `rkipc` before direct V4L2 capture because it owns the camera pipeline:

```sh
adb shell killall rkipc
```

On the current firmware, `/dev/video11` is the ISP main-path node and supports
NV12. Capture one frame to the device, pull it to the host, and convert it to
JPEG:

```sh
adb shell 'v4l2-ctl -d /dev/video11 \
  --set-fmt-video=width=2304,height=1296,pixelformat=NV12 \
  --stream-mmap=4 --stream-count=1 --stream-to=/tmp/frame.nv12'
adb pull /tmp/frame.nv12 .
ffmpeg -f rawvideo -pixel_format nv12 -video_size 2304x1296 \
  -i frame.nv12 -frames:v 1 frame.jpg
```

If the node number differs after a firmware change, identify the ISP main-path
node with `adb shell v4l2-ctl --list-devices`. Restart the stock application
stack when finished:

```sh
adb shell /etc/init.d/S21appinit start
```

## Testing PWM0 on the second LED

PWM0 uses GPIO1_PA2, which is connected to the second board LED. The ST7789
display node is commented out in the tracked DTSI because it previously used
the same pin as its D/C GPIO.

The device tree enables PWM0, assigns GPIO1_PA2 to it, and declares the LED as
a `pwm-leds` consumer. The consumer owns PWM0 and sets the board's required
`normal` polarity in the device tree. Use the LED class interface rather than
exporting the PWM channel manually.

After booting firmware built from the tracked DTSI, open a root shell on the
device:

```sh
adb shell
```

Verify the PWM device-tree node and LED class device:

```sh
cat /proc/device-tree/pwm@ff350000/status
ls -l /sys/class/leds
```

The device-tree status should report `okay`, and `/sys/class/leds` should
contain `pwm0_led`. Run the device-only test script from the device shell:

```sh
/usr/bin/test-pwm-led.sh
```

The script continuously cycles the LED and turns it off when interrupted.
Because the LED consumer owns PWM0, do not export `pwm0` manually through
`/sys/class/pwm`.

The init script can also be controlled manually from the device shell:

```sh
/etc/init.d/S99a-eye-night-vision start
/etc/init.d/S99a-eye-night-vision stop
/etc/init.d/S99a-eye-night-vision restart
```

On an IMX415 build, `S99a-eye-night-vision` supervises `/usr/bin/night-vision`.
The C++ controller asks `/usr/bin/night-vision-jpeg` for a sample every 10
seconds and uses its `mean_y` value. The defaults, calibrated from the supplied
SC3336 samples, turn night mode on below 100 and back off above 110 (0 is black,
255 is white); override them with
`--night-on`, `--day-on`, and `--interval-sec`. Night mode sets GPIO116 high and
the PWM LED to half of its reported maximum brightness. Day mode sets GPIO116
low and turns the LED off. Invalid or missing JPEG samples do not cause a mode
transition. The controller writes status and errors to `/tmp/night-vision.log`.
The optional shell implementation uses the same thresholds and controls the
same LED; on IMX415 it also controls the shutter. Stop the init service before
running it manually so the two controllers do not compete:

```sh
/etc/init.d/S99a-eye-night-vision stop
/usr/bin/night-vision.sh
```

`test-pwm-led.sh` remains installed for manual LED testing and is not called by
the init service. On SC3336, night mode changes the LED only and leaves the
camera's GPIO3_C4 reference-clock path alone.

## Optional: manually loading the module on the device

Manual upload and loading are optional. Use this method to test the module
without rebuilding and flashing the full image, or to load it on a running
device where it was not loaded at boot. The normal image build packages the
module in `/oem/usr/ko/` for startup loading.

From the host shell, copy the module to a temporary directory on the
board, then open an interactive shell on the device:

```sh
adb push sdk/luckfox-pico/sysdrv/source/objs_kernel/drv_ko/lib/modules/5.10.160/kernel/drivers/media/i2c/imx415.ko /tmp/imx415.ko
adb shell
```

The following commands are issued from the device shell after running
`adb shell`:

```sh
uname -r
id
ls -l /tmp/imx415.ko
insmod /tmp/imx415.ko
lsmod | grep imx415
dmesg | tail -n 80
```

If the device shell is not running as root, exit the shell and restart ADB as
root from the host shell before entering it again:

```sh
adb root
adb shell
```

Then repeat the device-shell commands above.

This temporary test does not modify the firmware image. It verifies module
compatibility with the running kernel. On firmware built with the `imx415`
argument, the IMX415 node is enabled and the module may probe the sensor;
on an older stock image, it will only load the module because the device tree
still describes the stock camera configuration.

If loading fails, capture the complete error and recent kernel log. Common
failures include an invalid module format, an ARM architecture mismatch,
missing symbols, or insufficient permissions.

## Editing the device tree

The tracked DTSI described in
[Tracked project files and SDK synchronization](#tracked-project-files-and-sdk-synchronization)
retains the supported sensor definitions. The root build script selects SC3336
or IMX415 in the copied SDK DTSI based on its camera argument (default:
IMX415); it enables that node,
disables the alternatives, and uses the selected sensor's D-PHY connection. Inspect the
nodes from the repository root:

```sh
grep -n -E "sc3336|sc4336|sc530ai|mipi|csi2|endpoint|ff470000" \
  kernel/rv1103-luckfox-pico-ipc.dtsi
```

Preserve both sensor nodes and their endpoint definitions. The working IMX415
configuration uses I²C address `0x37`, the camera module's onboard oscillator,
GPIO3_C4 as the night-mode shutter switch, GPIO3 PC5 as active-low reset, and
two CSI-2 lanes. The driver treats `xvclk` as optional for this configuration.
Its camera-module and lens names are `CMK-OT2022-PX1` and
`IR0147-36IRC-8M-F20`, matching the IQ file. The build selection changes the
active SC3336 and IMX415 node statuses in the SDK copy.

After editing the device tree, rebuild and package from the repository root:

```sh
./build.sh imx415
```

The full image build packages the kernel module and selected device tree
together. A module-only build does not update the device tree; device-tree
changes require a full image build and flash.

## Current device-tree integration

The tracked `kernel/rv1103-luckfox-pico-ipc.dtsi` keeps both supported camera
definitions and their separate D-PHY inputs. The root build script prepares
the SDK copy for the selected camera. It defaults to IMX415; omitting the
argument and passing `imx415` are equivalent. Pass `sc3336` to select the stock
camera:

- For `sc3336`, the SC3336 node is enabled and D-PHY input 0 connects to
  `sc3336_out`.
- For `imx415`, the IMX415 node is enabled and D-PHY input 3 connects to
  `imx415_out`.
- The other camera nodes are disabled in each generated SDK DTSI.
- IMX415 uses I²C address `0x37`, the camera module's onboard oscillator,
  GPIO3 PC5 as active-low reset, and GPIO3_C4 as the night-mode shutter switch
  in GPIO mode. SCxxxx nodes retain `MCLK_REF_MIPI0` and `mipi_refclk_out0`.
- IMX415 camera-module and lens names match the bundled tuning profile:
  `CMK-OT2022-PX1` and `IR0147-36IRC-8M-F20`.
- The ST7789 display node is commented out because its D/C signal used
  GPIO1_PA2.
- PWM0 uses GPIO1_PA2 and is exposed through a `pwm-leds` consumer named
  `pwm0_led` with normal polarity.
- The tracked kernel configuration enables `CONFIG_VIDEO_SC3336=m`,
  `CONFIG_VIDEO_IMX415=m`, and `CONFIG_LEDS_PWM=y`.

### Test the night-mode shutter GPIO

From a root shell on the device, export GPIO3_C4 and set it as an output. On
this RV1106 mapping, GPIO3_C4 is global GPIO 116 (bank 3 base 96 plus pin C4
offset 20):

```sh
echo 116 > /sys/class/gpio/export
echo out > /sys/class/gpio/gpio116/direction
echo 1 > /sys/class/gpio/gpio116/value
```

Set it low to test the other state, then release the GPIO when finished:

```sh
echo 0 > /sys/class/gpio/gpio116/value
echo 116 > /sys/class/gpio/unexport
```

The high and low states control the shutter; which state opens it depends on
the camera wiring.

The root-level build script is the required build entry point:

```sh
./build.sh
# Equivalent explicit IMX415 selection:
./build.sh imx415
# Or select the stock SC3336 camera:
./build.sh sc3336
```

After a successful build, the complete firmware image is available at:

```text
sdk/luckfox-pico/output/image/update.img
```

Flash it from the repository root with the local upgrade tool:

```sh
./sdk/upgrade_tool/upgrade_tool uf \
  ./sdk/luckfox-pico/output/image/update.img
```

## IMX415 two-lane 1080p sensor mode

The tracked driver is the patched Luckfox/RV1106 IMX415 driver used with the
Pico Mini. The 1080p addition is a new sensor mode, not a 1920x1080 sensor-pad
format: the driver includes a two-lane, linear RAW12 mode that reads the full
sensor field using 2x2 horizontal/vertical binning and outputs a 1944x1097
Bayer frame. The Rockchip CIF crop is `(left=12, top=8,
width=1920, height=1080)`, so the ISP receives Full HD. The existing
`rkipc-imx415-720p.ini` then scales/encodes that input as 1280x720 for the
application and RTSP stream. This avoids the narrow field of view produced by
the driver's older 1284x720 windowed mode; it does not claim zero edge-pixel
loss from the alignment crop.

The mode is `imx415_linear_12bit_1944x1097_445M_regs_2lane` in
`camera/imx415.c`, and it is the first entry in `supported_modes_2lane[]`.
The first entry is the default for a two-lane sensor. The driver reports the
sensor pad as `SGBRG12_1X12/1944x1097`; its selection rectangle describes the
1920x1080 crop to the downstream Rockchip pipeline.

### Mode timing and format

| Setting | Value | Meaning |
| --- | --- | --- |
| CSI-2 lanes | 2 | Matches the Pico Mini camera connection |
| XVCLK | 27 MHz | Sensor input clock |
| Link frequency | 445.5 MHz | 891 Mbps per lane |
| Sensor output | RAW12, SGBRG | Bayer data sent to the CIF |
| ADC conversion | 10 bit | Sensor conversion setting used with RAW12 output |
| Binning | 2x2 | Full-array readout, without the old 1284x720 window crop |
| Sensor pad | 1944x1097 | Binned frame before the CIF crop |
| CIF crop | `(12,8)`, 1920x1080 | Full HD image delivered to ISP |
| HMAX / VMAX | 1100 / 2700 | 1H and frame length in sensor timing units |
| Driver HTS / minimum VTS | 2200 / 2700 | Controls and frame timing; VTS cannot go below 2700 |
| Calculated pixel rate | 148.5 MHz | `445.5 MHz × 2 lanes × 2 / 12 bits` |
| Driver mode limit | 25 fps | `148.5 MHz / (2200 × 2700)` |
| Application profile | 20 fps | Requested source/destination rate and GOP in the INI |

The 25 fps value is the driver's mode ceiling. The tracked INI is set to 20 fps;
it is not an instruction to run the application stream at 25 fps.

### Key sensor register settings

The values below are the writes in the new mode array. Multi-byte values are
shown in increasing register-address order; the sensor interprets timing
register bytes as little-endian values.

| Register(s) | Value(s) | Purpose |
| --- | --- | --- |
| `0x3000`, `0x3002` at start | `01`, `01` | Hold the sensor in standby while programming the mode |
| `0x3008`, `0x300A` | `5D`, `42` | Mode clock/setup values |
| `0x301C` | `00` | Disable the old sensor window crop |
| `0x3020–0x3022` | `01`, `01`, `01` | Enable the binned readout configuration |
| `0x3024–0x3026` | `8C`, `0A`, `00` | VMAX = 2700 lines |
| `0x3028–0x3029` | `4C`, `04` | HMAX = 1100 clocks |
| `0x302C–0x302D` | `00`, `00` | Linear readout mode |
| `0x3031–0x3033` | `00`, `01`, `05` | ADC/output format and 891 Mbps-per-lane link setting |
| `0x3050–0x3052` | `08`, `00`, `00` | Initial SHR0 exposure timing; V4L2 controls update exposure |
| `0x30CF` | `00` | Linear-mode setting |
| `0x30D9–0x30DA` | `02`, `01` | Mode timing values |
| `0x3115–0x3116` | `00`, `23` | Two-lane timing values |
| `0x3118–0x311B` | `C6`, `00`, `E7`, `00` | Two-lane timing values |
| `0x311E` | `23` | Two-lane timing value |
| `0x3260`, `0x3701` | `01`, `00` | Binned readout settings |
| `0x4001` | `01` | Select two CSI-2 lanes |
| `0x4004–0x4005` | `C0`, `06` | Readout timing value (`0x06C0`) |
| `0x400C`, `0x4074` | `00`, `01` | Mode-specific readout settings |
| `0x4018–0x4029` | `7F 00 37 00 37 00 F7 00 3F 00 6F 00 3F 00 5F 00 2F 00` | Sensor readout timing table |

The mode array also contains the supporting sensor tuning and MIPI timing
writes in the `0x32xx`–`0x3Bxx` ranges. These values are part of the mode
programming sequence; keep them with the new mode when changing it. The array
ends by releasing master stop (`0x3002 = 0`) and waiting 30 ms, while leaving
standby asserted. The driver's stream-start path applies V4L2 controls and then
starts output by writing `0x3000 = 0`.

### What the driver patch changes

The patch adds the binned mode to the two-lane mode table and adds the exact
445.5 MHz link-frequency entry used by that mode. It adds per-mode `vts_min`
metadata so the new mode cannot be driven below 2700 lines per frame, and uses
that minimum when setting VBLANK controls. Mode changes also update exposure,
link-frequency, and pixel-rate control values. Frame-interval reporting uses
the selected mode's actual VTS, including extra vertical blanking. The
selection code reports the aligned 1920x1080 crop for the 1944x1097 pad. The
stream-start path now skips the global register array when a mode has no global
array, as is the case for these two-lane modes.

The older two-lane RAW12 full-resolution and 1284x720 windowed modes remain in
the table. Their mode arrays explicitly restore their own windowing, binning,
format, and timing settings so switching modes does not inherit the new mode's
register state. The driver mode and INI rate are implemented; end-to-end frame,
image-quality, restart, and reboot validation is tracked in
[implementation-plan.md](implementation-plan.md).

## Related documentation

See [camera.md](camera.md) for board and pipeline details,
[implementation-plan.md](implementation-plan.md) for remaining validation.
