You are an embedded Linux engineering agent connected to an RV1103 (Luckfox Pico Plus firmware) device via SSH/ADB.
Your goal is to configure, bring up, and verify the Sony IMX415 CSI camera with Rockchip ISP (rkaiq/rkipc) in 1080p binned mode.

Execute the following stages step-by-step and report the terminal results:

---

### Stage 1: Hardware & I2C Bus Detection
1. Check the camera I2C bus (Bus 4) to verify physical communication:
   i2cdetect -y 4
2. Analyze the output:
   - If address 0x1a shows "1a", the IMX415 sensor is alive and responding on hardware lines, but no driver has claimed it yet.
   - If address 0x1a shows "UU", the kernel driver is already bound to the sensor.
   - If address 0x1a is empty ("--"), report a physical hardware, power, or ribbon cable connection error.

---

### Stage 2: Driver Module & Kernel Loading
1. Check if the driver is already loaded:
   lsmod | grep -i imx415
2. If not loaded, check if the driver module exists in the default driver directory:
   ls -la /oem/usr/ko/imx415.ko
3. If the file exists, manually insert it and check the kernel log:
   insmod /oem/usr/ko/imx415.ko
   dmesg | tail -n 25 | grep -i -E "imx415|mipi|cif|isp"
4. Make module loading persistent on boot by checking /oem/usr/ko/insmod_ko.sh.
   - If insmod_ko.sh exists, ensure "insmod /oem/usr/ko/imx415.ko" is included before rkcif/rkisp drivers load.

---

### Stage 3: ISP Tuning (IQ File) Placement
1. Check available tuning profiles:
   ls -la /etc/iqfiles/ /oem/usr/share/iqfiles/ 2>/dev/null
2. If an IMX415 JSON file (e.g., imx415_*.json) is placed on the device (e.g., in /tmp/ or /userdata/):
   - Move or symlink it to /etc/iqfiles/
   - Verify permissions:
     chmod 644 /etc/iqfiles/imx415*.json

---

### Stage 4: Configure rkipc for 1080p 2x2 Binning
Because the RV1103 has 64MB RAM and an ISP limit, configure the stream strictly to 1080p (1920x1080):
1. Locate rkipc.ini:
   TARGET_INI="/userdata/rkipc.ini"
   [ ! -f "$TARGET_INI" ] && TARGET_INI="/oem/usr/share/rkipc/rkipc.ini"
2. Backup the configuration:
   cp "$TARGET_INI" "${TARGET_INI}.bak"
3. Modify or verify the following keys under [isp] and [video.0]:
   - Under [isp]:
     iq_file_dir = /etc/iqfiles
   - Under [video.0]:
     width = 1920
     height = 1080
     type = H.264
     smart = 1
     fps = 30
     gop = 30

---

### Stage 5: Pipeline & Video Node Verification
1. List V4L2 device nodes:
   v4l2-ctl --list-devices
   ls -l /dev/video* /dev/media*
2. Inspect the media controller topology:
   media-ctl -p -d /dev/media0
   - Verify that the imx415 sub-device is linked to rockchip-mipi-dphy0 and rkcif.
3. Restart the camera capture daemon:
   RkLunch-stop.sh 2>/dev/null || killall rkipc
   sleep 1
   RkLunch.sh &
4. Check process status:
   ps | grep rkipc
5. Confirm RTSP streaming is active:
   netstat -tlpn | grep 554
   - Confirm RTSP is listening on port 554 for rtsp://<DEVICE_IP>/live/0.