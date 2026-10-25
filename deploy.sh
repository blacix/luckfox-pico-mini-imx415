#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE="${ROOT_DIR}/sdk/luckfox-pico/sysdrv/source/objs_kernel/drv_ko/lib/modules/5.10.160/kernel/drivers/media/i2c/imx415.ko"
LED_TEST="${ROOT_DIR}/overlay/a-eye/usr/bin/test-pwm-led.sh"
RKIPC_SUPERVISOR="${ROOT_DIR}/overlay/a-eye/usr/bin/rkipc-supervisor.sh"
INIT_SCRIPT="${ROOT_DIR}/overlay/a-eye/etc/init.d/S99a-eye-night-vision"
NIGHT_VISION_CONFIG="${ROOT_DIR}/overlay/a-eye/etc/default/a-eye-night-vision"
NIGHT_VISION_SHELL_SCRIPT="${ROOT_DIR}/overlay/a-eye/usr/bin/night-vision.sh"
NIGHT_VISION_SERVICE_BIN="${ROOT_DIR}/sdk/luckfox-pico/project/app/out/root/usr/bin/night-vision"
NIGHT_VISION_IMAGE_PROCESSOR_BIN="${ROOT_DIR}/sdk/luckfox-pico/project/app/out/root/usr/bin/night-vision-jpeg"
CAMERA_INIT="${ROOT_DIR}/overlay/a-eye/etc/init.d/S99a-eye-cam"
CAMERA_INI="${ROOT_DIR}/camera/rkipc-imx415-720p.ini"
CAMERA_IQ="${ROOT_DIR}/camera/imx415_CMK-OT2022-PX1_IR0147-36IRC-8M-F20.json"
REMOTE_MODULE=/tmp/imx415.ko
REMOTE_SCRIPT=/tmp/test-pwm-led.sh
REMOTE_RKIPC_SUPERVISOR=/tmp/rkipc-supervisor.sh
REMOTE_INIT=/tmp/S99a-eye-night-vision
REMOTE_NIGHT_VISION_CONFIG=/tmp/a-eye-night-vision
REMOTE_NIGHT_VISION_SHELL_SCRIPT=/tmp/night-vision.sh
REMOTE_NIGHT_VISION_SERVICE_BIN=/tmp/night-vision
REMOTE_NIGHT_VISION_IMAGE_PROCESSOR_BIN=/tmp/night-vision-jpeg
REMOTE_CAMERA_INIT=/tmp/S99a-eye-cam
REMOTE_CAMERA_INI=/tmp/rkipc-imx415-720p.ini
REMOTE_CAMERA_IQ=/tmp/imx415_CMK-OT2022-PX1_IR0147-36IRC-8M-F20.json
INSTALLED_SCRIPT=/usr/bin/test-pwm-led.sh
INSTALLED_RKIPC_SUPERVISOR=/usr/bin/rkipc-supervisor.sh
INSTALLED_INIT=/etc/init.d/S99a-eye-night-vision
INSTALLED_NIGHT_VISION_CONFIG=/etc/default/a-eye-night-vision
INSTALLED_NIGHT_VISION_SHELL_SCRIPT=/usr/bin/night-vision.sh
INSTALLED_NIGHT_VISION_SERVICE_BIN=/usr/bin/night-vision
INSTALLED_NIGHT_VISION_IMAGE_PROCESSOR_BIN=/usr/bin/night-vision-jpeg
INSTALLED_CAMERA_INIT=/etc/init.d/S99a-eye-cam
INSTALLED_CAMERA_INI=/usr/share/rkipc-imx415-720p.ini
INSTALLED_CAMERA_IQ=/usr/share/iqfiles/imx415_CMK-OT2022-PX1_IR0147-36IRC-8M-F20.json
INSTALLED_MODULE=/oem/usr/ko/imx415.ko

if [[ ! -f "${MODULE}" ]]; then
    echo "Missing kernel module: ${MODULE}" >&2
    echo "Build the kernel driver first." >&2
    exit 1
fi

if [[ ! -f "${LED_TEST}" ]]; then
    echo "Missing LED test script: ${LED_TEST}" >&2
    exit 1
fi

if [[ ! -f "${RKIPC_SUPERVISOR}" ]]; then
	echo "Missing rkipc supervisor: ${RKIPC_SUPERVISOR}" >&2
	exit 1
fi

if [[ ! -f "${INIT_SCRIPT}" ]]; then
    echo "Missing init script: ${INIT_SCRIPT}" >&2
    exit 1
fi

if [[ ! -f "${NIGHT_VISION_CONFIG}" ]]; then
    echo "Missing night-vision configuration: ${NIGHT_VISION_CONFIG}" >&2
    exit 1
fi

if [[ ! -f "${NIGHT_VISION_SHELL_SCRIPT}" ]]; then
    echo "Missing optional night-vision shell controller: ${NIGHT_VISION_SHELL_SCRIPT}" >&2
    exit 1
fi

if [[ ! -f "${NIGHT_VISION_SERVICE_BIN}" ]]; then
    echo "Missing night-vision service executable: ${NIGHT_VISION_SERVICE_BIN}" >&2
    echo "Build the SDK application packages first." >&2
    exit 1
fi

if [[ ! -f "${NIGHT_VISION_IMAGE_PROCESSOR_BIN}" ]]; then
    echo "Missing JPEG image-processor executable: ${NIGHT_VISION_IMAGE_PROCESSOR_BIN}" >&2
    echo "Build the SDK application packages first." >&2
    exit 1
fi

if [[ ! -f "${CAMERA_INIT}" ]]; then
    echo "Missing camera init script: ${CAMERA_INIT}" >&2
    exit 1
fi

if [[ ! -f "${CAMERA_INI}" ]]; then
    echo "Missing camera INI file: ${CAMERA_INI}" >&2
    exit 1
fi

if [[ ! -f "${CAMERA_IQ}" ]]; then
    echo "Missing camera IQ file: ${CAMERA_IQ}" >&2
    exit 1
fi

adb get-state >/dev/null

echo "Pushing IMX415 kernel module"
adb push "${MODULE}" "${REMOTE_MODULE}"

echo "Pushing LED test script"
adb push "${LED_TEST}" "${REMOTE_SCRIPT}"

echo "Pushing rkipc supervisor"
adb push "${RKIPC_SUPERVISOR}" "${REMOTE_RKIPC_SUPERVISOR}"

echo "Pushing init script"
adb push "${INIT_SCRIPT}" "${REMOTE_INIT}"

echo "Pushing night-vision configuration"
adb push "${NIGHT_VISION_CONFIG}" "${REMOTE_NIGHT_VISION_CONFIG}"

echo "Pushing optional night-vision shell controller"
adb push "${NIGHT_VISION_SHELL_SCRIPT}" "${REMOTE_NIGHT_VISION_SHELL_SCRIPT}"

echo "Pushing night-vision service and JPEG image processor"
adb push "${NIGHT_VISION_SERVICE_BIN}" "${REMOTE_NIGHT_VISION_SERVICE_BIN}"
adb push "${NIGHT_VISION_IMAGE_PROCESSOR_BIN}" "${REMOTE_NIGHT_VISION_IMAGE_PROCESSOR_BIN}"

echo "Pushing camera init script and configuration"
adb push "${CAMERA_INIT}" "${REMOTE_CAMERA_INIT}"
adb push "${CAMERA_INI}" "${REMOTE_CAMERA_INI}"
adb push "${CAMERA_IQ}" "${REMOTE_CAMERA_IQ}"

echo "Installing files and restarting the camera services"
adb shell "
    test \"\$(id -u)\" = 0
    if [ -x '${INSTALLED_INIT}' ]; then
        '${INSTALLED_INIT}' stop
    fi
    if [ -x '${INSTALLED_CAMERA_INIT}' ]; then
        '${INSTALLED_CAMERA_INIT}' stop
    else
        killall rkipc 2>/dev/null || true
    fi
    if grep -q '^imx415 ' /proc/modules; then
        rmmod imx415
    fi
    chmod 0755 '${REMOTE_NIGHT_VISION_SHELL_SCRIPT}'
    mv '${REMOTE_NIGHT_VISION_SHELL_SCRIPT}' '${INSTALLED_NIGHT_VISION_SHELL_SCRIPT}'
    chmod 0755 '${REMOTE_SCRIPT}'
    mv '${REMOTE_SCRIPT}' '${INSTALLED_SCRIPT}'
    chmod 0755 '${REMOTE_RKIPC_SUPERVISOR}'
    mv '${REMOTE_RKIPC_SUPERVISOR}' '${INSTALLED_RKIPC_SUPERVISOR}'
    chmod 0755 '${REMOTE_INIT}'
    mv '${REMOTE_INIT}' '${INSTALLED_INIT}'
    mkdir -p /etc/default
    mv '${REMOTE_NIGHT_VISION_CONFIG}' '${INSTALLED_NIGHT_VISION_CONFIG}'
    chmod 0755 '${REMOTE_NIGHT_VISION_SERVICE_BIN}' '${REMOTE_NIGHT_VISION_IMAGE_PROCESSOR_BIN}'
    mv '${REMOTE_NIGHT_VISION_SERVICE_BIN}' '${INSTALLED_NIGHT_VISION_SERVICE_BIN}'
    mv '${REMOTE_NIGHT_VISION_IMAGE_PROCESSOR_BIN}' '${INSTALLED_NIGHT_VISION_IMAGE_PROCESSOR_BIN}'
    chmod 0755 '${REMOTE_CAMERA_INIT}'
    mv '${REMOTE_CAMERA_INIT}' '${INSTALLED_CAMERA_INIT}'
    mv '${REMOTE_CAMERA_INI}' '${INSTALLED_CAMERA_INI}'
    mkdir -p /usr/share/iqfiles
    mv '${REMOTE_CAMERA_IQ}' '${INSTALLED_CAMERA_IQ}'
    mkdir -p /oem/usr/ko
    mv '${REMOTE_MODULE}' '${INSTALLED_MODULE}'
    insmod '${INSTALLED_MODULE}'
    '${INSTALLED_CAMERA_INIT}' start
    '${INSTALLED_INIT}' restart
    test -x '${INSTALLED_SCRIPT}'
    test -x '${INSTALLED_RKIPC_SUPERVISOR}'
    test -x '${INSTALLED_INIT}'
    test -x '${INSTALLED_NIGHT_VISION_SHELL_SCRIPT}'
    test -x '${INSTALLED_NIGHT_VISION_SERVICE_BIN}'
    test -x '${INSTALLED_NIGHT_VISION_IMAGE_PROCESSOR_BIN}'
    test -x '${INSTALLED_CAMERA_INIT}'
    test -f '${INSTALLED_CAMERA_INI}'
    test -f '${INSTALLED_CAMERA_IQ}'
    grep '^imx415 ' /proc/modules
"

echo "Deployment complete"
echo "Run on the device: ${INSTALLED_SCRIPT}"
echo "Init script: ${INSTALLED_INIT}"
echo "Camera service: ${INSTALLED_CAMERA_INIT}"
