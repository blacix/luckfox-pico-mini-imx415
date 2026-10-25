# Sony IMX415 Camera Support on LuckFox Pico Mini

## Goal

Use a Sony IMX415 camera with a LuckFox Pico Mini board.

The board does not appear to support IMX415 directly in its installed image. The objective is to determine whether IMX415 support can be added using Rockchip/LuckFox kernel drivers,
device-tree configuration, camera tuning files, and a rebuilt firmware image.

The camera is connected to the board, which is accessible through ADB.

## Confirmed Board Information

The connected device reports:

```text
Model: Luckfox Pico Mini
SoC: RV1103G
Device-tree compatible:
rockchip,rv1103g-38x38-ipc-v10
rockchip,rv1103

Kernel:
Linux 5.10.160
ARMv7
Build date: June 11, 2025

Operating system:
Buildroot 2023.02.6
Firmware version: uboot-06/26/2025

RAM:
Total: approximately 32.9 MB
Available: approximately 17.6 MB

Storage:
SPI NAND

The device was detected through ADB:

da38a30f0d450808    device

## Current Camera Configuration

The running device tree contains an SC3336 sensor node:

/proc/device-tree/i2c@ff470000/sc3336@30/compatible
/proc/device-tree/i2c@ff470000/sc3336@30/name

The sensor is configured at I²C address 0x30.

The current boot log contains:

sc3336 4-0030: driver version: 00.01.01
sc3336 4-0030: Failed to get reset-gpios
sc3336 4-0030: could not get default pinstate
sc3336 4-0030: could not get sleep pinstate
sc3336 4-0030: supply avdd not found, using dummy regulator
sc3336 4-0030: supply dovdd not found, using dummy regulator
sc3336 4-0030: supply dvdd not found, using dummy regulator
sc3336 4-0030: Unexpected sensor id(000000), ret(-5)

This indicates that the current image is attempting to probe an SC3336 sensor, not an IMX415.

Installed camera-related kernel modules include:

sc3336.ko
phy-rockchip-csi2-dphy-hw.ko
phy-rockchip-csi2-dphy.ko
video_rkcif.ko
video_rkisp.ko

There is no installed imx415.ko.

The installed IQ/tuning files are:

mis5001_CMK-OT2115-PC1_30IRC-F16.json
sc3336_CMK-OT2119-PC1_30IRC-F16.json
sc4336_OT01_40IRC_F16.json

There is no IMX415 IQ file in:

/oem/usr/share/iqfiles

## Current Video Pipeline

The board has Rockchip CSI, RKCIF, and RKISP components loaded.

Kernel modules currently loaded include:

phy_rockchip_csi2_dphy
phy_rockchip_csi2_dphy_hw
video_rkisp
video_rkcif
rk_dvbm

Available devices include:

/dev/media0
/dev/media1
/dev/video0 ... /dev/video20
/dev/v4l-subdev0
/dev/v4l-subdev1
/dev/v4l-subdev2

V4L2 reports:

rkisp-statistics:
/dev/video19
/dev/video20

rkcif-mipi-lvds:
/dev/media0

rkisp_mainpath:
/dev/video11
/dev/video12
/dev/video13
/dev/video14
/dev/video15
/dev/video16
/dev/video17
/dev/video18
/dev/media1

The RKCIF media topology contains CSI input links, but there is no successfully detected terminal sensor.

The media topology reports:

rkcif-mipi-lvds
rockchip-mipi-csi2
stream_cif_mipi_id0
stream_cif_mipi_id1
stream_cif_mipi_id2
stream_cif_mipi_id3
rkcif_scale_ch0
rkcif_scale_ch1
rkcif_scale_ch2
rkcif_scale_ch3

Opening /dev/video0 currently fails:

Failed to open /dev/video0: No such device

This is consistent with the sensor not being detected or the current device-tree configuration not matching the connected camera.

## RV1103 Hardware Limitations

LuckFox documents the RV1103 family as having:

ISP maximum input: 4 MP at 30 fps
Camera interface: 1 × 2-lane MIPI CSI
Memory: 64 MB DDR2 on the normal RV1103 boards

Sources:

- https://wiki.luckfox.com/Luckfox-Pico/Luckfox-Pico-RV1103/
- https://www.luckfox.com/EN-Luckfox-Pico
- https://files.luckfox.com/wiki/Luckfox-Pico/PDF/Rockchip%20RV1103%20Datasheet%20V1.1-20220427.pdf

The Sony IMX415 is an approximately 8 MP sensor, normally producing:

3840 × 2160

Therefore, the RV1103 ISP is not expected to process the full native IMX415 output reliably.

The most realistic mode is a reduced or binned mode, such as:

1944 × 1097

This is approximately 2.1 MP and fits within the RV1103 ISP input limit.

## Existing LuckFox IMX415 Driver

The current LuckFox Pico SDK contains an IMX415 driver:

sysdrv/source/kernel/drivers/media/i2c/imx415.c

Source:

https://raw.githubusercontent.com/LuckfoxTECH/luckfox-pico/main/sysdrv/source/kernel/drivers/media/i2c/imx415.c

The driver registers the sensor using:

compatible = "sony,imx415";

It also supports:

I²C sensor detection
V4L2 subdevice registration
Rockchip camera-module metadata
CSI-2 lane configuration
Multiple image modes
Linear and HDR configurations
Two-lane and four-lane operation

The corresponding Kconfig entry exists:

config VIDEO_IMX415
tristate "Sony IMX415 sensor support"

Source:

https://raw.githubusercontent.com/LuckfoxTECH/luckfox-pico/main/sysdrv/source/kernel/drivers/media/i2c/Kconfig

The driver includes two-lane modes:

3864 × 2192 at approximately 15 fps
1284 × 720 at approximately 90 fps
3864 × 2192 at approximately 15 fps using 10-bit output

The driver also contains reduced-resolution/binned modes around:

1944 × 1097

The driver defines the IMX415 native pixel array as:

3864 × 2192

The two-lane mode uses:

IMX415_2LANES

and a 27 MHz or 37 MHz sensor clock depending on the selected mode.

## Important Compatibility Question

The LuckFox Pico Mini has a two-lane MIPI CSI interface.

The exact IMX415 camera module must therefore be checked carefully.

Required information:

Camera module manufacturer
Camera module model
Connector pinout
MIPI lane count
I²C address
Sensor clock requirement
Power rail requirements
Reset or power-down GPIO requirements
Whether the module supports two-lane operation

Many IMX415 modules are designed for four-lane MIPI CSI-2. Some IMX415 driver implementations support two-lane modes, but the physical module must also support that mode.

A four-lane-only module will not be directly compatible with the Pico Mini's two-lane CSI connection.

## LuckFox Boards That Officially Support IMX415

LuckFox documents IMX415 support for boards including:

Luckfox Pico Zero
Luckfox Aura
Luckfox Omni3576

The Pico Zero documentation specifically describes an IMX415 camera:

Sensor: IMX415
Resolution: 8 MP

Source:

https://wiki.luckfox.com/Luckfox-Pico-Zero/CSI-Camera/

The Pico Zero is based on RV1106 rather than RV1103. The official instructions state that an IMX415-specific firmware image must be flashed so that RKIPC uses the proper camera
configuration.

The Pico Zero documentation is useful as a reference for:

Device-tree structure
RKIPC configuration
IMX415 IQ files
Camera-module metadata
Power and GPIO configuration
Camera startup procedure

However, an RV1106 image must not simply be flashed onto the RV1103 Pico Mini. The SoC, memory, peripherals, and board device tree differ.

## LuckFox SDK Board Support

The official LuckFox SDK contains board targets for both RV1103 and RV1106:

RV1103_Luckfox_Pico
RV1103_Luckfox_Pico_Mini
RV1103_Luckfox_Pico_Plus
RV1103_Luckfox_Pico_WebBee

RV1106_Luckfox_Pico_Pro_Max
RV1106_Luckfox_Pico_Ultra
RV1106_Luckfox_Pico_Pi
RV1106_Luckfox_Pico_Zero

Source:

https://github.com/LuckfoxTECH/luckfox-pico

The SDK uses Linux kernel 5.10.160, matching the kernel version running on the board.

The official SDK repository currently contains:

IMX415 driver source
IMX415 Kconfig entry
RV1103 device-tree files
RV1106 device-tree files
RKISP/RKCIF/CSI drivers
RKIPC camera application code
Camera IQ files for supported sensors

## Current RV1103 Device Tree

The official RV1103 camera device tree uses an SC3336 node similar to:

&i2c4 {
status = "okay";
clock-frequency = <400000>;
pinctrl-names = "default";
pinctrl-0 = <&i2c4m2_xfer>;

sc3336: sc3336@30 {
  compatible = "smartsens,sc3336";
  status = "okay";
  reg = <0x30>;

  clocks = <&cru MCLK_REF_MIPI0>;
  clock-names = "xvclk";

  pwdn-gpios = <&gpio3 RK_PC5 GPIO_ACTIVE_HIGH>;

  pinctrl-names = "default";
  pinctrl-0 = <&mipi_refclk_out0>;

  rockchip,camera-module-index = <0>;
  rockchip,camera-module-facing = "back";
  rockchip,camera-module-name = "CMK-OT2119-PC1";
  rockchip,camera-module-lens-name = "30IRC-F16";

  port {
      sc3336_out: endpoint {
          remote-endpoint = <&csi_dphy_input0>;
          data-lanes = <1 2>;
      };
  };
};
};

The CSI side is configured for two lanes:

data-lanes = <1 2>;

Source:

https://github.com/LuckfoxTECH/luckfox-pico/blob/main/sysdrv/source/kernel/arch/arm/boot/dts/rv1103-luckfox-pico-ipc.dtsi

An IMX415 port would need to preserve the RV1103-specific CSI/RKCIF/ISP graph while replacing the sensor-specific node and metadata.

## Likely Device-Tree Changes

The SC3336 node would likely need to be replaced with something structurally similar to:

&i2c4 {
status = "okay";
clock-frequency = <400000>;
pinctrl-names = "default";
pinctrl-0 = <&i2c4m2_xfer>;

imx415: imx415@1a {
  compatible = "sony,imx415";
  status = "okay";
  reg = <0x1a>;

  /* The camera module supplies xvclk from its onboard oscillator. */

  /*
   * These GPIO and regulator properties must be adapted
   * to the actual camera module and board wiring.
   */
  // reset-gpios = <...>;
  // pwdn-gpios = <...>;
  // avdd-supply = <...>;
  // dovdd-supply = <...>;
  // dvdd-supply = <...>;

  pinctrl-names = "default";
  pinctrl-0 = <&gpio3_c4>;

  rockchip,camera-module-index = <0>;
  rockchip,camera-module-facing = "back";
  rockchip,camera-module-name = "CUSTOM-IMX415";
  rockchip,camera-module-lens-name = "DEFAULT";

  port {
      imx415_out: endpoint {
          remote-endpoint = <&csi_dphy_input0>;
          data-lanes = <1 2>;
      };
  };
};
};

The address 0x1a is only an example. The actual address must be determined from the camera module documentation or by checking the module with an I²C probe.

For the module-clock configuration, the device-tree node does not request a
SoC `xvclk`; the driver accepts its absence and leaves the module oscillator
in control. GPIO3_C4 is muxed as GPIO and controls the night-mode shutter. The
oscillator frequency still needs to match the selected sensor mode.

The following must not be copied blindly:

I²C address
module oscillator frequency and sensor-mode timing
reset GPIO
power-down GPIO
power rail names
GPIO polarity
camera connector lane mapping
camera module metadata

## Likely Kernel Build Changes

The IMX415 driver must be built into the kernel or compiled as a module.

Possible configuration:

CONFIG_VIDEO_IMX415=y

or:

CONFIG_VIDEO_IMX415=m

If built as a module, the resulting file would be:

imx415.ko

It must match the running kernel exactly:

Linux 5.10.160
ARMv7
same kernel configuration
same compiler ABI
same kernel symbol versions, if enabled

A module built for another Rockchip board, another architecture, or another kernel version should not be assumed to work.

The safer approach is to rebuild the complete board-specific kernel and device tree using the LuckFox Pico SDK.

## Likely Camera Software Changes

After the kernel driver and device tree are working, RKIPC will probably need configuration changes.

Relevant components include:

RKIPC
rkaiq_3A_server
camera IQ files
rkipc.ini
RK_MPI camera initialization

The existing RKIPC configuration is currently intended for sensors such as:

SC3336
SC4336
MIS5001

An IMX415 IQ file may be needed for proper:

Auto exposure
Auto white balance
Auto gain
Lens shading correction
Noise reduction
Color correction
HDR behavior

A raw V4L2 stream should be tested before trying to make RKIPC and RKAIQ work. This separates:

Sensor detection problems
CSI lane/timing problems
ISP pipeline problems
RKAIQ tuning/configuration problems
RKIPC application configuration problems

## Recommended Development Sequence

### 1. Identify the Camera Module

Determine:

Exact module name
I²C address
Two-lane or four-lane MIPI operation
Sensor clock frequency
Power supply voltages
Reset/power-down signals
Connector orientation

This is the most important missing information.

### 2. Obtain or Inspect the LuckFox SDK

Use the official SDK:

https://github.com/LuckfoxTECH/luckfox-pico

Use the RV1103 Pico Mini board configuration, not an RV1106 board configuration.

### 3. Enable the IMX415 Driver

Enable:

CONFIG_VIDEO_IMX415=y

or compile it as a module:

CONFIG_VIDEO_IMX415=m

### 4. Create an RV1103 IMX415 Device Tree

Start from the existing RV1103 Pico Mini/IPC device tree.

Replace:

smartsens,sc3336

with:

sony,imx415

Preserve the RV1103 CSI pipeline.

Use two-lane links if supported:

data-lanes = <1 2>;

Configure the actual sensor power and GPIO wiring.

### 5. Build a Test Image

Build:

kernel
device tree
IMX415 driver
required modules

Do not flash an RV1106 image onto the RV1103 Pico Mini.

### 6. Validate Sensor Detection

After booting the test image, inspect:

dmesg | grep -i imx415
dmesg | grep -i csi
dmesg | grep -i rkcif
dmesg | grep -i rkisp
media-ctl -p -d /dev/media0
v4l2-ctl --list-devices

A successful probe should identify:

sony,imx415

and report a valid sensor ID rather than:

Unexpected sensor id(000000)

### 7. Test a Reduced-Resolution Mode

The first target should be approximately:

1944 × 1097

or another mode below 4 MP.

Avoid starting with:

3840 × 2160

because the RV1103 ISP maximum input is documented as 4 MP.

### 8. Test Raw Capture

Test the sensor and CSI pipeline without RKAIQ/RKIPC first.

Only after raw capture succeeds should the following be enabled:

RKISP
RKAIQ
RKIPC
RTSP

### 9. Add or Adapt IQ Configuration

Once sensor detection and capture work, add an IMX415 IQ configuration and configure RKIPC to use it.

## Main Risks

### ISP Resolution Limit

The RV1103 ISP is documented for a maximum of 4 MP input. Full IMX415 resolution is approximately 8 MP.

### MIPI Lane Compatibility

The Pico Mini exposes two-lane CSI. The exact IMX415 module may require four lanes.

### Camera Electrical Wiring

The sensor may require specific:

1.1 V digital supply
1.8 V I/O supply
2.9 V analog supply
27 MHz or 37 MHz clock
reset signal
power-down signal

The exact values depend on the camera module implementation.

### Very Limited RAM

The connected board reports only approximately 32.9 MB total RAM. Building or running Ubuntu-based camera stacks may be impractical. Buildroot and the existing lightweight Rockchip
userspace are more appropriate.

### Driver/Kernel ABI Matching

An IMX415 module copied from another image may not load if it was built against a different:

kernel version
kernel configuration
compiler ABI
symbol table
architecture

### IQ File Compatibility

A sensor driver can detect and stream images without a proper IQ file, but image quality and RKAIQ operation may be poor or fail.

## Current Conclusion

IMX415 support is technically possible to investigate on the LuckFox Pico Mini because:

The RV1103 has a functional CSI/RKCIF/RKISP pipeline.
The LuckFox SDK contains an IMX415 driver.
The driver includes two-lane modes.
The driver includes reduced-resolution modes.
The kernel version matches the LuckFox SDK family.

However, full 8 MP operation through the RV1103 ISP is unlikely because:

RV1103 ISP maximum input is documented as 4 MP.
The Pico Mini has only a two-lane CSI interface.
The current image contains no IMX415 driver.
The current device tree is configured for SC3336.
The current image contains no IMX415 IQ file.
The exact IMX415 module wiring is not yet known.

The most realistic target is:

Sony IMX415
2-lane MIPI CSI-2
approximately 1944 × 1097
RV1103 RKCIF/RKISP
custom kernel and device tree
custom or adapted IQ configuration

No firmware, kernel, device tree, or files on the board were modified during this research.

