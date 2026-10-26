# JPEG channel measurement tools

`capture-rkipc-jpeg-adb.sh` requests one JPEG through the running RKIPC
service, then pulls the newest snapshot from `/userdata/video0` over ADB. It
does not change the LED, IR-cut, or ISP mode.

```sh
adb devices
adb shell /etc/init.d/S99a-eye-night-vision stop

# Capture the LED-off baseline in day position.
adb shell 'echo 1 > /sys/class/gpio/gpio116/value; echo 0 > /sys/class/leds/pwm0_led/brightness'
camera/night-vision/jpeg-processing/tools/capture-rkipc-jpeg-adb.sh build/captures/day-led-off.jpg

# Keep GPIO116 in the same position to isolate the LED's effect.
adb shell 'echo 127 > /sys/class/leds/pwm0_led/brightness'
camera/night-vision/jpeg-processing/tools/capture-rkipc-jpeg-adb.sh build/captures/day-led-on.jpg
adb shell 'echo 0 > /sys/class/leds/pwm0_led/brightness'

# Optional: capture the actual night hardware state (active-low GPIO116).
adb shell 'echo 0 > /sys/class/gpio/gpio116/value; echo 127 > /sys/class/leds/pwm0_led/brightness'
camera/night-vision/jpeg-processing/tools/capture-rkipc-jpeg-adb.sh build/captures/night.jpg

adb shell /etc/init.d/S99a-eye-night-vision start
```

The day-position pair leaves the IR-cut position fixed, so its channel delta
isolates the effect of switching the IR LED. The optional night capture shows
the combined IR-cut and LED change. GPIO116 is active-low for night on this
board. The RKIPC ISP stays in day/color mode during these captures because the
supervisor is stopped; the capture helper itself does not request an ISP mode.

Analyze one image or compare two images with Pillow on the host:

```sh
python3 -m pip install Pillow
camera/night-vision/jpeg-processing/tools/analyze-rgb.py \
  build/captures/day-led-off.jpg build/captures/day-led-on.jpg
```

The analyzer converts images to RGB, downsamples to at most 288x162, and
reports per-channel mean and percentiles. In a two-image comparison it prints
the mean red, green, and blue deltas (second image minus first). These are
decoded JPEG channel values; they are not sensor raw Bayer values.
