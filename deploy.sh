#!/usr/bin/env bash

set -euo pipefail
set -x

if [[ "$#" -gt 1 ]]; then
	echo "Usage: $0 [DEVICE_IP]" >&2
	exit 2
fi

DEPLOY_TRANSPORT=adb
SSH_TARGET=
SSH_CONTROL_DIR=
SSH_CONTROL_PATH=
if [[ "$#" -eq 1 ]]; then
	DEPLOY_TRANSPORT=ssh
	SSH_TARGET="root@$1"
	for tool in ssh scp; do
		if ! command -v "$tool" >/dev/null 2>&1; then
			echo "Missing required SSH client command: $tool" >&2
			echo "Install it with: sudo apt install openssh-client" >&2
			exit 1
		fi
	done
fi

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE="${ROOT_DIR}/sdk/luckfox-pico/sysdrv/source/objs_kernel/drv_ko/lib/modules/5.10.160/kernel/drivers/media/i2c/imx415.ko"
LED_TEST="${ROOT_DIR}/overlay/a-eye/usr/bin/test-pwm-led.sh"
RKIPC_SUPERVISOR="${ROOT_DIR}/overlay/a-eye/usr/bin/rkipc-supervisor.sh"
INIT_SCRIPT="${ROOT_DIR}/overlay/a-eye/etc/init.d/S99a-eye-night-vision"
NIGHT_VISION_CONFIG="${ROOT_DIR}/overlay/a-eye/etc/default/a-eye-night-vision"
NIGHT_VISION_SHELL_SCRIPT="${ROOT_DIR}/overlay/a-eye/usr/bin/night-vision.sh"
NIGHT_VISION_SERVICE_BIN="${ROOT_DIR}/sdk/luckfox-pico/project/app/out/root/usr/bin/night-vision"
NIGHT_VISION_MEASUREMENT_BIN="${ROOT_DIR}/sdk/luckfox-pico/project/app/out/root/usr/bin/night-vision-measurement"
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
REMOTE_NIGHT_VISION_MEASUREMENT_BIN=/tmp/night-vision-measurement
REMOTE_CAMERA_INIT=/tmp/S99a-eye-cam
REMOTE_CAMERA_INI=/tmp/rkipc-imx415-720p.ini
REMOTE_CAMERA_IQ=/tmp/imx415_CMK-OT2022-PX1_IR0147-36IRC-8M-F20.json
INSTALLED_SCRIPT=/usr/bin/test-pwm-led.sh
INSTALLED_RKIPC_SUPERVISOR=/usr/bin/rkipc-supervisor.sh
INSTALLED_INIT=/etc/init.d/S99a-eye-night-vision
INSTALLED_NIGHT_VISION_CONFIG=/etc/default/a-eye-night-vision
INSTALLED_NIGHT_VISION_SHELL_SCRIPT=/usr/bin/night-vision.sh
INSTALLED_NIGHT_VISION_SERVICE_BIN=/usr/bin/night-vision
INSTALLED_NIGHT_VISION_MEASUREMENT_BIN=/usr/bin/night-vision-measurement
RETIRED_NIGHT_VISION_JPEG_BIN=/usr/bin/night-vision-jpeg
INSTALLED_CAMERA_INIT=/etc/init.d/S99a-eye-cam
INSTALLED_CAMERA_INI=/usr/share/rkipc-imx415-720p.ini
INSTALLED_CAMERA_IQ=/usr/share/iqfiles/imx415_CMK-OT2022-PX1_IR0147-36IRC-8M-F20.json
INSTALLED_MODULE=/oem/usr/ko/imx415.ko

start_ssh_master() {
	SSH_CONTROL_DIR="$(mktemp -d "${TMPDIR:-/tmp}/a-eye-deploy.XXXXXX")"
	SSH_CONTROL_PATH="${SSH_CONTROL_DIR}/control"
	ssh -M -N -f \
		-o ControlMaster=yes \
		-o ControlPersist=60 \
		-o ControlPath="$SSH_CONTROL_PATH" \
		"$SSH_TARGET"
}

stop_ssh_master() {
	if [[ -n "$SSH_CONTROL_PATH" ]]; then
		ssh -S "$SSH_CONTROL_PATH" -O exit "$SSH_TARGET" >/dev/null 2>&1 || true
	fi
	if [[ -n "$SSH_CONTROL_DIR" ]]; then
		rm -rf "$SSH_CONTROL_DIR"
	fi
}

push_file() {
	local source="$1"
	local destination="$2"
	if [[ "$DEPLOY_TRANSPORT" == adb ]]; then
		adb push "$source" "$destination"
	else
		scp -o ControlPath="$SSH_CONTROL_PATH" \
			"$source" "${SSH_TARGET}:${destination}"
	fi
}

remote_exec() {
	if [[ "$DEPLOY_TRANSPORT" == adb ]]; then
		adb shell "$@"
	else
		ssh -S "$SSH_CONTROL_PATH" "$SSH_TARGET" "$@"
	fi
}

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

if [[ ! -f "${NIGHT_VISION_MEASUREMENT_BIN}" ]]; then
    echo "Missing night-vision measurement executable: ${NIGHT_VISION_MEASUREMENT_BIN}" >&2
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

if [[ "$DEPLOY_TRANSPORT" == adb ]]; then
	if ! command -v adb >/dev/null 2>&1; then
		echo "Missing required command: adb" >&2
		exit 1
	fi
	adb get-state >/dev/null
else
	trap stop_ssh_master EXIT
	start_ssh_master
	REMOTE_UID="$(remote_exec id -u)"
	if [[ "$REMOTE_UID" != 0 ]]; then
		echo "SSH deployment requires root login (tried ${SSH_TARGET})." >&2
		exit 1
	fi
fi

echo "Pushing IMX415 kernel module"
push_file "${MODULE}" "${REMOTE_MODULE}"

echo "Pushing LED test script"
push_file "${LED_TEST}" "${REMOTE_SCRIPT}"

echo "Pushing rkipc supervisor"
push_file "${RKIPC_SUPERVISOR}" "${REMOTE_RKIPC_SUPERVISOR}"

echo "Pushing init script"
push_file "${INIT_SCRIPT}" "${REMOTE_INIT}"

echo "Pushing night-vision configuration"
push_file "${NIGHT_VISION_CONFIG}" "${REMOTE_NIGHT_VISION_CONFIG}"

echo "Pushing optional night-vision shell controller"
push_file "${NIGHT_VISION_SHELL_SCRIPT}" "${REMOTE_NIGHT_VISION_SHELL_SCRIPT}"

echo "Pushing night-vision service and JPEG image processor"
push_file "${NIGHT_VISION_SERVICE_BIN}" "${REMOTE_NIGHT_VISION_SERVICE_BIN}"
push_file "${NIGHT_VISION_MEASUREMENT_BIN}" "${REMOTE_NIGHT_VISION_MEASUREMENT_BIN}"

echo "Pushing camera init script and configuration"
push_file "${CAMERA_INIT}" "${REMOTE_CAMERA_INIT}"
push_file "${CAMERA_INI}" "${REMOTE_CAMERA_INI}"
push_file "${CAMERA_IQ}" "${REMOTE_CAMERA_IQ}"

echo "Installing files and restarting the camera services via ${DEPLOY_TRANSPORT}"
remote_exec sh -s <<REMOTE_INSTALL
    set -ex
    if [ -x '${INSTALLED_INIT}' ]; then
        '${INSTALLED_INIT}' stop
    fi
    if [ -x '${INSTALLED_CAMERA_INIT}' ]; then
        '${INSTALLED_CAMERA_INIT}' stop
    else
        killall rkipc 2>/dev/null || true
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
    chmod 0755 '${REMOTE_NIGHT_VISION_SERVICE_BIN}' '${REMOTE_NIGHT_VISION_MEASUREMENT_BIN}'
    mv '${REMOTE_NIGHT_VISION_SERVICE_BIN}' '${INSTALLED_NIGHT_VISION_SERVICE_BIN}'
    mv '${REMOTE_NIGHT_VISION_MEASUREMENT_BIN}' '${INSTALLED_NIGHT_VISION_MEASUREMENT_BIN}'
    rm -f '${RETIRED_NIGHT_VISION_JPEG_BIN}'
    chmod 0755 '${REMOTE_CAMERA_INIT}'
    mv '${REMOTE_CAMERA_INIT}' '${INSTALLED_CAMERA_INIT}'
    mv '${REMOTE_CAMERA_INI}' '${INSTALLED_CAMERA_INI}'
    mkdir -p /usr/share/iqfiles
    mv '${REMOTE_CAMERA_IQ}' '${INSTALLED_CAMERA_IQ}'
    mkdir -p /oem/usr/ko
    mv '${REMOTE_MODULE}' '${INSTALLED_MODULE}'
    '${INSTALLED_CAMERA_INIT}' start
    '${INSTALLED_INIT}' restart
    test -x '${INSTALLED_SCRIPT}'
    test -x '${INSTALLED_RKIPC_SUPERVISOR}'
    test -x '${INSTALLED_INIT}'
    test -x '${INSTALLED_NIGHT_VISION_SHELL_SCRIPT}'
    test -x '${INSTALLED_NIGHT_VISION_SERVICE_BIN}'
    test -x '${INSTALLED_NIGHT_VISION_MEASUREMENT_BIN}'
    test -x '${INSTALLED_CAMERA_INIT}'
    test -f '${INSTALLED_CAMERA_INI}'
    test -f '${INSTALLED_CAMERA_IQ}'
    grep '^imx415 ' /proc/modules
REMOTE_INSTALL

echo "Deployment complete"
echo "Run on the device: ${INSTALLED_SCRIPT}"
echo "Init script: ${INSTALLED_INIT}"
echo "Camera service: ${INSTALLED_CAMERA_INIT}"
