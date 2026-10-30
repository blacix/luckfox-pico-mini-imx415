# IMX415 frame-rate settings and limits

## Current configuration

The Pico Mini's IMX415 path uses the two-lane RAW12, 2x2-binned sensor mode.
The sensor pad is 1944x1097; the camera pipeline crops it to 1920x1080, then
`rkipc` scales the encoded main stream to 1280x720.

The tracked driver mode in `camera/imx415.c` declares a 25 fps ceiling:

- MIPI link frequency: 445.5 MHz, corresponding to 891 Mb/s per lane.
- Sensor HMAX: 1100; driver HTS: 2200.
- Sensor VMAX and minimum VTS: 2700.
- Calculated pixel rate: 148.5 MHz; `148.5 MHz / (2200 x 2700) = 25 fps`.

The `vts_min = 2700` constraint means VBLANK cannot reduce the frame length
below the value used for 25 fps. It can lower the frame rate by increasing
VTS, but this driver mode does not currently expose a faster interval.

The tracked `camera/rkipc-imx415-720p.ini` now requests 25 fps in the encoder's
source and destination rates and both ISP adjustment sections. Its GOP and
virtual IDR interval are also 25 frames; these control keyframe spacing, not
the capture frame rate itself. The SDK build script stages this tracked INI
into the root filesystem overlay.

The matching IQ JSON has `CISMinFps = 10` and
`AecFrameRateMode.isFpsFix = 0`, with `FpsValue = 15`. Since fixed-FPS mode is
disabled, `FpsValue` should not be treated as a confirmed hard 15 fps cap.
Its effect on AE behavior has not been verified, so it is left unchanged.

## Can this mode run at 30 fps?

The IMX415 sensor supports 30 fps in a two-lane 2x2-binned mode, but Sony's
published timing table specifies 1782 or 2079 Mb/s per lane for those 30 fps
settings. The RV1103 datasheet specifies a maximum MIPI CSI D-PHY rate of
1.5 Gb/s per lane. Those documented 30 fps settings exceed the receiver's
specified lane rate. ([Sony IMX415 datasheet](https://dl.khadas.com/products/add-ons/imx415/datasheet/sony-imx415-datasheet.pdf),
[Rockchip RV1103 datasheet](https://rockchip.fr/RV1103%20datasheet%20V1.5.pdf))

Therefore, the sensor's 30 fps capability does not establish that 30 fps is
available through this Pico Mini two-lane camera path. The current mode's
891 Mb/s-per-lane link and 25 fps timing are within the RV1103 receiver's
stated limit. The project has no validated 30 fps mode for this receiver.
Changing the INI request alone cannot raise the driver's ceiling or resolve
the documented lane-rate mismatch.

## Validation status

The INI requests 25 fps, but actual delivered frame rate still needs to be
measured on the Pico Mini. The implementation plan calls for counting distinct
captured frames over at least 60 seconds while checking CSI/CIF error counters.
An encoder or RTSP rate setting is a request, not proof of the sensor's
delivered frame rate.

The extracted project's earlier measurements are for different modes: its
native 1284x720 window delivered about 27.5 fps but narrows the field of view;
its wide 8 MP mode delivered about 20 fps. Those results do not validate the
current full-field binned 1080p mode.
