#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SDK_DIR="${ROOT_DIR}/sdk/luckfox-pico"
CAMERA="${1:-imx415}"
DTSI_SOURCE="${ROOT_DIR}/kernel/rv1103-luckfox-pico-ipc.dtsi"
DTSI_TARGET="${SDK_DIR}/sysdrv/source/kernel/arch/arm/boot/dts/rv1103-luckfox-pico-ipc.dtsi"
BOARD_DTS_TARGET="${SDK_DIR}/sysdrv/source/kernel/arch/arm/boot/dts/rv1103g-luckfox-pico-mini.dts"
KERNEL_CONFIG_SOURCE="${ROOT_DIR}/kernel/luckfox_rv1106_linux_defconfig"
KERNEL_CONFIG_TARGET="${SDK_DIR}/sysdrv/source/kernel/arch/arm/configs/luckfox_rv1106_linux_defconfig"
OVERLAY_SOURCE="${ROOT_DIR}/overlay/a-eye"
OVERLAY_TARGET="${SDK_DIR}/project/cfg/BoardConfig_IPC/overlay/overlay-luckfox-buildroot-init"
INIT_TARGET="${OVERLAY_TARGET}/etc/init.d"
BIN_TARGET="${OVERLAY_TARGET}/usr/bin"
CAMERA_DRIVER_SOURCE="${ROOT_DIR}/camera/imx415.c"
CAMERA_DRIVER_TARGET="${SDK_DIR}/sysdrv/source/kernel/drivers/media/i2c/imx415.c"
CAMERA_INI_SOURCE="${ROOT_DIR}/camera/rkipc-imx415-720p.ini"
CAMERA_IQ_SOURCE="${ROOT_DIR}/camera/imx415_CMK-OT2022-PX1_IR0147-36IRC-8M-F20.json"
CAMERA_INI_TARGET="${OVERLAY_TARGET}/usr/share/rkipc-imx415-720p.ini"
CAMERA_IQ_TARGET="${OVERLAY_TARGET}/usr/share/iqfiles/imx415_CMK-OT2022-PX1_IR0147-36IRC-8M-F20.json"
NIGHT_VISION_SERVICE_SOURCE="${ROOT_DIR}/camera/night-vision/jpeg-processing/night-vision-service"
NIGHT_VISION_SERVICE_TARGET="${SDK_DIR}/project/app/a-eye-night-vision-service"
NIGHT_VISION_IMAGE_PROCESSOR_SOURCE="${ROOT_DIR}/camera/night-vision/jpeg-processing/image-processor"
NIGHT_VISION_IMAGE_PROCESSOR_TARGET="${SDK_DIR}/project/app/a-eye-night-vision-jpeg"
NIGHT_VISION_COMMON_SOURCE="${ROOT_DIR}/camera/night-vision/common"

if [[ "$#" -gt 1 ]]; then
    echo "Usage: $0 [sc3336|imx415] (default: imx415)" >&2
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

if [[ ! -f "${BOARD_DTS_TARGET}" ]]; then
    echo "Missing Pico Mini board DTS: ${BOARD_DTS_TARGET}" >&2
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

if [[ ! -f "${NIGHT_VISION_SERVICE_SOURCE}/Makefile" ||
      ! -f "${NIGHT_VISION_SERVICE_SOURCE}/night-vision.cpp" ]]; then
    echo "Missing night-vision service source or Makefile" >&2
    exit 1
fi

if [[ ! -f "${NIGHT_VISION_IMAGE_PROCESSOR_SOURCE}/Makefile" ||
      ! -f "${NIGHT_VISION_IMAGE_PROCESSOR_SOURCE}/main.cpp" ||
      ! -f "${NIGHT_VISION_COMMON_SOURCE}/brightness_metrics.h" ||
      ! -f "${NIGHT_VISION_IMAGE_PROCESSOR_SOURCE}/tjpgd3/src/tjpgd.c" ]]; then
    echo "Missing JPEG night-vision application source or TJpgDec files" >&2
    exit 1
fi

if [[ "${CAMERA}" == "imx415" ]]; then
    if [[ ! -f "${CAMERA_INI_SOURCE}" ]]; then
        echo "Missing tracked IMX415 rkipc profile: ${CAMERA_INI_SOURCE}" >&2
        exit 1
    fi

    if [[ ! -f "${CAMERA_IQ_SOURCE}" ]]; then
        echo "Missing tracked IMX415 IQ file: ${CAMERA_IQ_SOURCE}" >&2
        exit 1
    fi
fi

if [[ ! -x "${SDK_DIR}/build.sh" ]]; then
    echo "Missing SDK build script: ${SDK_DIR}/build.sh" >&2
    exit 1
fi

echo "Removing previously installed project camera files from the SDK overlay"
mkdir -p "${OVERLAY_TARGET}"
# Clear the last build's project services and IMX415-only files before applying
# the requested camera selection.
rm -f -- "${INIT_TARGET}"/S99a-eye*
rm -f -- \
    "${BIN_TARGET}/rkipc-supervisor.sh" \
    "${BIN_TARGET}/night-vision.sh" \
    "${CAMERA_INI_TARGET}" \
    "${CAMERA_IQ_TARGET}"

echo "Copying tracked DTSI into the SDK for ${CAMERA}"
cp -- "${DTSI_SOURCE}" "${DTSI_TARGET}"

echo "Enabling the integrated Ethernet PHY in the Pico Mini DTS"
sed -i \
    -e '/^&gmac {/,/^};/ s/status = "disabled";/status = "okay";/' \
    "${BOARD_DTS_TARGET}"

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

echo "Preparing project files in the SDK rootfs overlay"
mkdir -p "${INIT_TARGET}" "${BIN_TARGET}"
cp -- "${OVERLAY_SOURCE}/etc/init.d/S99a-eye-night-vision" "${INIT_TARGET}/"
cp -- "${OVERLAY_SOURCE}/usr/bin/test-pwm-led.sh" "${BIN_TARGET}/"
cp -- "${OVERLAY_SOURCE}/usr/bin/night-vision.sh" "${BIN_TARGET}/"
chmod 0755 "${BIN_TARGET}/night-vision.sh"

if [[ "${CAMERA}" == "imx415" ]]; then
    echo "Installing IMX415 camera service and configuration into the SDK overlay"
    cp -- "${OVERLAY_SOURCE}/etc/init.d/S99a-eye-cam" "${INIT_TARGET}/"
    cp -- "${OVERLAY_SOURCE}/usr/bin/rkipc-supervisor.sh" "${BIN_TARGET}/"
    mkdir -p "$(dirname -- "${CAMERA_IQ_TARGET}")"
    cp -- "${CAMERA_INI_SOURCE}" "${CAMERA_INI_TARGET}"
    cp -- "${CAMERA_IQ_SOURCE}" "${CAMERA_IQ_TARGET}"
fi

echo "Copying tracked IMX415 driver into the SDK kernel source tree"
cp -- "${CAMERA_DRIVER_SOURCE}" "${CAMERA_DRIVER_TARGET}"

echo "Staging the JPEG image processor for the SDK application build"
mkdir -p \
    "${NIGHT_VISION_IMAGE_PROCESSOR_TARGET}/common" \
    "${NIGHT_VISION_IMAGE_PROCESSOR_TARGET}/tjpgd3/src"
cp -- "${NIGHT_VISION_IMAGE_PROCESSOR_SOURCE}/Makefile" \
    "${NIGHT_VISION_IMAGE_PROCESSOR_TARGET}/Makefile"
cp -- "${NIGHT_VISION_IMAGE_PROCESSOR_SOURCE}/main.cpp" \
    "${NIGHT_VISION_IMAGE_PROCESSOR_TARGET}/main.cpp"
cp -- "${NIGHT_VISION_COMMON_SOURCE}/brightness_metrics.h" \
    "${NIGHT_VISION_IMAGE_PROCESSOR_TARGET}/common/brightness_metrics.h"
cp -- \
    "${NIGHT_VISION_IMAGE_PROCESSOR_SOURCE}/tjpgd3/src/tjpgd.c" \
    "${NIGHT_VISION_IMAGE_PROCESSOR_SOURCE}/tjpgd3/src/tjpgd.h" \
    "${NIGHT_VISION_IMAGE_PROCESSOR_SOURCE}/tjpgd3/src/tjpgdcnf.h" \
    "${NIGHT_VISION_IMAGE_PROCESSOR_TARGET}/tjpgd3/src/"

echo "Staging the night-vision service for the SDK application build"
mkdir -p "${NIGHT_VISION_SERVICE_TARGET}"
cp -- "${NIGHT_VISION_SERVICE_SOURCE}/Makefile" \
    "${NIGHT_VISION_SERVICE_TARGET}/Makefile"
cp -- "${NIGHT_VISION_SERVICE_SOURCE}/night-vision.cpp" \
    "${NIGHT_VISION_SERVICE_TARGET}/night-vision.cpp"
cp -- "${NIGHT_VISION_SERVICE_SOURCE}/rkipc_saturation.cpp" \
    "${NIGHT_VISION_SERVICE_TARGET}/rkipc_saturation.cpp"
cp -- "${NIGHT_VISION_SERVICE_SOURCE}/rkipc_saturation.h" \
    "${NIGHT_VISION_SERVICE_TARGET}/rkipc_saturation.h"

cd "${SDK_DIR}"

echo "Building the complete SDK image set"
./build.sh all

echo "Packaging update.img"
./build.sh updateimg

echo "Build complete: ${SDK_DIR}/output/image/update.img"
