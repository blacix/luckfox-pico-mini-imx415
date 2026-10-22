# Implementation Guide: Native 1080p@25fps via On-Sensor 2×2 Binning on RV1103 + IMX415

## 1. Goal and Problem Analysis

### The Failure of the 720p Subsampled Mode
The previous attempt to reach 25+ fps using `1284x720` failed the Field of View (FOV) requirement:
* In Sony's IMX415 register architecture, `1284x720` is implemented as an **ROI window crop**, which reads only the central $1284 \times 720$ pixel region of the silicon. This acts as an optical telephoto crop (~3× zoom) and discards the edges of the scene.
* The 8MP mode (`3864x2192`) downscaled via CIF preserves wide FOV, but saturates the 2-lane D-PHY bus and vertical blanking interval, physically capping throughput at **~20.6 fps**.

### The Solution: Sony Mode 4 (2×2 Binning)
To obtain **full optical FOV at 25+ fps in 1080p**, the sensor must run in **Sony Mode 4 (All-Pixel 2×2 Binning)**:
* **Optical Coverage:** Exposes all $3864 \times 2192$ physical photodiode sites across the full die. Adjacent $2 \times 2$ pixel groups are binned on-chip into a single logical pixel before readout.
* **CIF Line Buffer:** Readout width is 1920 pixels, well under the RV1103 CIF hardware line limit of 3072 pixels (zero edge cropping).
* **Throughput:** Data payload is reduced by 75% relative to 8MP, allowing 2-lane MIPI CSI-2 to run at **25.0–30.0 fps** with zero frame loss.

---

## 2. Phase 1: Kernel Driver Modification (`imx415.c`)

The compiled `imx415.ko` module on the board currently registers only `3864x2192` and `1284x720` in its `supported_modes_2lane[]` table. The 1080p binning mode must be enabled and recompiled.

### Step 2.1: Locate the Driver Source on Host
In the kernel tree:
```bash
find . -name "imx415.c" -path "*/drivers/media/i2c/*"

Step 2.2: Check for Existing 1080p Register Tables
Rockchip vendor drivers frequently include 1080p register tables (imx415_1080p_regs or imx415_linear_1080p_regs) mapped exclusively to supported_modes_4lane[]. Check for existing definitions:

Bash
grep -n -E "1080|1920" drivers/media/i2c/imx415.c
Step 2.3: Register Sony Mode 4 in supported_modes_2lane
In drivers/media/i2c/imx415.c, add the 1080p entry to supported_modes_2lane[]:
C
static const struct imx415_mode supported_modes_2lane[] = {
    {
        .width = 1920,
        .height = 1080,
        .max_fps = {
            .numerator = 10000,
            .denominator = 250000, /* 25.0 fps */
        },
        .exp_def = 0x08ca - 0x08,
        .hts_def = 0x044c * 2,
        .vts_def = 0x08ca,
        .bpp = 10,
        .bus_fmt = MEDIA_BUS_FMT_SGBRG10_1X10,
        .reg_list = imx415_1080p_2lane_regs,
        .hdr_mode = NO_HDR,
        .vc[0] = V4L2_MBUS_CSI2_CHANNEL_0,
    },
    /* Retain existing 8MP and 720p fallback modes below */
};

Step 2.4: Configure Hardware Binning Registers
If imx415_1080p_2lane_regs is not already defined in imx415.c, define the register initialization sequence with Sony's binning controls:

0x3000 = 0x01 (Standby mode during configuration)

0x3008 = 0x01 (CSI-2 2-lane mode)

0x3018 = 0x00 (RAW10 mode)

0x3020 = 0x02 (Vertical 2/2-line binning enable)

0x3022 = 0x01 (Horizontal 2-fold binning enable)

0x3000 = 0x00 (Operating mode)

Step 2.5: Build and Deploy the Kernel Module
Compile the kernel module using the Luckfox cross-compiler:

Bash
make ARCH=arm CROSS_COMPILE=arm-rockchip830-linux-uclibcgnueabihf- modules M=drivers/media/i2c/
Transfer imx415.ko to the target board:

Bash
adb push drivers/media/i2c/imx415.ko /userdata/imx415.ko
Test module insertion on the target:

Bash
killall -9 rkipc 2>/dev/null
rmmod imx415
insmod /userdata/imx415.ko

# Confirm 1920x1080 is enumerated on pad 0
v4l2-ctl -d /dev/v4l-subdev2 --list-subdev-framesizes pad=0,code=0x300e
Acceptance Gate: Output must explicitly report:

Plaintext
Size Range: 1920x1080 - 1920x1080
3. Phase 2: Pipeline Configuration (rkipc_custom.ini)
Update /userdata/rkipc_custom.ini to handle the 1080p resolution and provide a 25 fps CBR stream.

Ini, TOML
[video.source]
enable_aiq = 1
enable_vo = 0
vo_dev_id = 3
enable_ivs = 0
enable_jpeg = 0
enable_venc_0 = 1
enable_venc_1 = 0
enable_venc_2 = 0
enable_npu = 0
npu_fps = 10
enable_rtsp = 1
enable_rtmp = 0
rotation = 0

[video.0]
buffer_size = 2073600 ; 1920 * 1080
buffer_count = 4
enable_refer_buffer_share = 1
stream_type = mainStream
video_type = compositeStream
max_width = 1920
max_height = 1080
width = 1920
height = 1080
rc_mode = CBR
rc_quality = high
src_frame_rate_den = 1
src_frame_rate_num = 25
dst_frame_rate_den = 1
dst_frame_rate_num = 25
target_rate = 3500
mid_rate = 3500
max_rate = 4096
min_rate = 2048
output_data_type = H.264
smart = close
h264_profile = high
gop = 25
smartp_viridrlen = 25
gop_mode = normalP
stream_smooth = 50
enable_motion_deblur = 0
motion_deblur_strength = 0
enable_motion_static_switch = 0
frame_min_i_qp = 18
frame_min_qp = 20
frame_max_i_qp = 36
frame_max_qp = 38
scalinglist = 0
enable_debreath_effect = 0
debreath_effect_strength = 16
thrd_i = 0,0,0,0,3,3,5,5,8,8,8,15,15,20,25,25
thrd_p = 0,0,0,0,3,3,5,5,8,8,8,15,15,20,25,25
aq_step_i = -8,-7,-6,-5,-4,-3,-2,-1,0,1,2,3,4,5,7,8
aq_step_p = -8,-7,-6,-5,-4,-3,-2,-1,0,1,2,3,4,5,7,8
qbias_enable = 1
qbias_i = 171
qbias_p = 85
flt_str_i = 0
flt_str_p = 0
cu_dqp = 1
anti_ring = 2
anti_line = 2
lambds = 4

[video.jpeg]
width = 1920
height = 1080
jpeg_buffer_size = 2097152
jpeg_qfactor = 70
enable_cycle_snapshot = 0
snapshot_interval_ms = 1000

[isp]
scenario = normal
init_form_ini = 1
normal_scene = day
custom1_scene = night
ircut_open_gpio = -1
ircut_close_gpio = -1

[isp.0.adjustment]
contrast = 50
brightness = 50
saturation = 50
sharpness = 50
fps = 25
hue = 50

[isp.0.exposure]
iris_type = auto
exposure_mode = auto
gain_mode = auto
auto_iris_level = 5
auto_exposure_enabled = 1
audo_gain_enabled = 1
exposure_time = 1/25
exposure_gain = 1

[isp.0.night_to_day]
night_to_day = day
night_to_day_filter_level = 5
night_to_day_filter_time = 5
ircut_filter_action = day
over_exposure_suppress = open
over_exposure_suppress_type = auto
fill_light_mode = IR
brightness_adjustment_mode = auto
light_brightness = 1
distance_level = 1
4. Phase 3: Runtime Launcher Script
Update /userdata/scripts/start_camera.sh to enforce the subdevice media format before executing rkipc:

Bash
#!/bin/sh
source /etc/profile.d/RkEnv.sh

MODE="${1:-1080p}"

killall -9 rkipc 2>/dev/null
sleep 1

case "$MODE" in
    1080p)
        echo "Configuring IMX415 for 1080p (2x2 Binning, Full FOV, 25fps)..."
        media-ctl -d /dev/media0 --set-v4l2 '"m00_b_imx415 4-0037":0[fmt:SGBRG10_1X10/1920x1080]'
        ;;
    8mp)
        echo "Configuring IMX415 for 8MP (Full Sensor, ~20fps)..."
        media-ctl -d /dev/media0 --set-v4l2 '"m00_b_imx415 4-0037":0[fmt:SGBRG12_1X12/3864x2192]'
        ;;
    native)
        echo "Configuring IMX415 for 720p (Center Crop / Zoom, 27.5fps)..."
        media-ctl -d /dev/media0 --set-v4l2 '"m00_b_imx415 4-0037":0[fmt:SGBRG12_1X12/1284x720]'
        ;;
    *)
        echo "Error: Unknown mode '$MODE'. Valid options: 1080p | 8mp | native"
        exit 1
        ;;
esac

# Confirm subdevice pad format
v4l2-ctl -d /dev/v4l-subdev2 --get-subdev-fmt 0

exec rkipc -c /userdata/rkipc_custom.ini -a /oem/usr/share/iqfiles
Ensure execution flag is set:

Bash
chmod +x /userdata/scripts/start_camera.sh
5. Phase 4: Acceptance Testing & Verification
Run these verifications from the macOS host:

1. Stream Format and Frame Rate
Inspect the stream parameters over TCP:

Bash
ffprobe -v error -select_streams v:0 \
  -show_entries stream=width,height,r_frame_rate,avg_frame_rate \
  -rtsp_transport tcp rtsp://10.15.116.182:554/live/0
Required Output: width=1920, height=1080, r_frame_rate=25/1 (or higher).

2. Optical Field of View (FOV) Verification
Capture a reference frame from the new stream:

Bash
ffmpeg -y -rtsp_transport tcp -i rtsp://10.15.116.182:554/live/0 -vframes 1 /tmp/test_1080p_fov.png
Required Result: The image boundaries must match the wide 8MP framing (image/log/fov_left-8mp-crop_vs_right-native-1284x720.png). Objects on the perimeter (window, water cooler, desk edge) must remain visible in the scene.

3. Error Log Audit
Check the kernel message ring buffer on the board:

Bash
dmesg | tail -n 40 | grep -i -E "csi|cif|rkisp|frameloss|ErrCnt"
Required Result: frameloss:0, csi size err:0, all err count:0.