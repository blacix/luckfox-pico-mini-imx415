#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SDK_DIR="${ROOT_DIR}/sdk/luckfox-pico"
CAMERA="${1:-}"
DTSI_SOURCE="${ROOT_DIR}/kernel/rv1103-luckfox-pico-ipc.dtsi"
DTSI_TARGET="${SDK_DIR}/sysdrv/source/kernel/arch/arm/boot/dts/rv1103-luckfox-pico-ipc.dtsi"
KERNEL_CONFIG_SOURCE="${ROOT_DIR}/kernel/luckfox_rv1106_linux_defconfig"
KERNEL_CONFIG_TARGET="${SDK_DIR}/sysdrv/source/kernel/arch/arm/configs/luckfox_rv1106_linux_defconfig"
OVERLAY_SOURCE="${ROOT_DIR}/overlay/a-eye"
OVERLAY_TARGET="${SDK_DIR}/project/cfg/BoardConfig_IPC/overlay/overlay-luckfox-buildroot-init"
CAMERA_DRIVER_SOURCE="${ROOT_DIR}/camera/imx415.c"
CAMERA_DRIVER_TARGET="${SDK_DIR}/sysdrv/source/kernel/drivers/media/i2c/imx415.c"
CAMERA_INI_SOURCE="${ROOT_DIR}/camera/rkipc-imx415-720p.ini"
CAMERA_IQ_SOURCE="${ROOT_DIR}/camera/imx415_CMK-OT2022-PX1_IR0147-36IRC-8M-F20.json"
CAMERA_FILES_TARGET="${OVERLAY_TARGET}/usr/share"

if [[ "$#" -ne 1 ]]; then
    echo "Usage: $0 {sc3336|imx415}" >&2
    exit 2
fi

case "${CAMERA}" in
    sc3336|imx415)
        ;;
    *)
        echo "Unsupported camera '${CAMERA}'. Choose 'sc3336' or 'imx415'." >&2
        exit 2
        ;;
esac

if [[ ! -f "${DTSI_SOURCE}" ]]; then
    echo "Missing tracked DTSI: ${DTSI_SOURCE}" >&2
    exit 1
fi

if [[ ! -f "${KERNEL_CONFIG_SOURCE}" ]]; then
    echo "Missing tracked kernel config: ${KERNEL_CONFIG_SOURCE}" >&2
    exit 1
fi

if [[ ! -d "${OVERLAY_SOURCE}" ]]; then
    echo "Missing tracked rootfs overlay: ${OVERLAY_SOURCE}" >&2
    exit 1
fi

if [[ ! -f "${CAMERA_DRIVER_SOURCE}" ]]; then
    echo "Missing tracked IMX415 camera driver: ${CAMERA_DRIVER_SOURCE}" >&2
    exit 1
fi

if [[ ! -f "${CAMERA_INI_SOURCE}" ]]; then
    echo "Missing tracked IMX415 rkipc profile: ${CAMERA_INI_SOURCE}" >&2
    exit 1
fi

if [[ ! -f "${CAMERA_IQ_SOURCE}" ]]; then
    echo "Missing tracked IMX415 IQ file: ${CAMERA_IQ_SOURCE}" >&2
    exit 1
fi

if [[ ! -x "${SDK_DIR}/build.sh" ]]; then
    echo "Missing SDK build script: ${SDK_DIR}/build.sh" >&2
    exit 1
fi

echo "Copying tracked DTSI into the SDK for ${CAMERA}"
cp -- "${DTSI_SOURCE}" "${DTSI_TARGET}"

if [[ "${CAMERA}" == "sc3336" ]]; then
    echo "Selecting SC3336 in the SDK DTSI"
    sed -i \
        -e '/sc3336: sc3336@30/,/port {/ s/status = "disabled";/status = "okay";/' \
        -e '/imx415: imx415@37/,/port {/ s/status = "okay";/status = "disabled";/' \
        "${DTSI_TARGET}"
else
    echo "Selecting IMX415 in the SDK DTSI"
    sed -i \
        -e '/sc3336: sc3336@30/,/port {/ s/status = "okay";/status = "disabled";/' \
        -e '/imx415: imx415@37/,/port {/ s/status = "disabled";/status = "okay";/' \
        "${DTSI_TARGET}"
fi

echo "Copying tracked kernel config into the SDK"
cp -- "${KERNEL_CONFIG_SOURCE}" "${KERNEL_CONFIG_TARGET}"

echo "Copying tracked rootfs overlay into the SDK"
mkdir -p "${OVERLAY_TARGET}"
cp -a -- "${OVERLAY_SOURCE}/." "${OVERLAY_TARGET}/"

echo "Copying tracked IMX415 driver into the SDK kernel source tree"
cp -- "${CAMERA_DRIVER_SOURCE}" "${CAMERA_DRIVER_TARGET}"

echo "Copying tracked IMX415 camera configuration into the SDK rootfs overlay"
mkdir -p "${CAMERA_FILES_TARGET}/iqfiles"
cp -a -- "${CAMERA_INI_SOURCE}" "${CAMERA_FILES_TARGET}/rkipc-imx415-720p.ini"
cp -a -- "${CAMERA_IQ_SOURCE}" \
    "${CAMERA_FILES_TARGET}/iqfiles/imx415_CMK-OT2022-PX1_IR0147-36IRC-8M-F20.json"

cd "${SDK_DIR}"

echo "Building the complete SDK image set"
./build.sh all

echo "Packaging update.img"
./build.sh updateimg

echo "Build complete: ${SDK_DIR}/output/image/update.img"
