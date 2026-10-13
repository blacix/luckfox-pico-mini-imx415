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

if [[ ! -x "${SDK_DIR}/build.sh" ]]; then
    echo "Missing SDK build script: ${SDK_DIR}/build.sh" >&2
    exit 1
fi

echo "Copying tracked DTSI into the SDK for ${CAMERA}"
cp -- "${DTSI_SOURCE}" "${DTSI_TARGET}"

if [[ "${CAMERA}" == "sc3336" ]]; then
    echo "Selecting SC3336 in the SDK DTSI"
    sed -i \
        -e '/csi_dphy_input0: endpoint@0/,/data-lanes = <1 2>;/ s@remote-endpoint = <&imx415_out>;@remote-endpoint = <\&sc3336_out>;@' \
        -e '/sc3336: sc3336@30/,/port {/ s/status = "disabled";/status = "okay";/' \
        -e '/imx415: imx415@30/,/port {/ s/status = "okay";/status = "disabled";/' \
        "${DTSI_TARGET}"
fi

echo "Copying tracked kernel config into the SDK"
cp -- "${KERNEL_CONFIG_SOURCE}" "${KERNEL_CONFIG_TARGET}"

echo "Copying tracked rootfs overlay into the SDK"
mkdir -p "${OVERLAY_TARGET}"
cp -a -- "${OVERLAY_SOURCE}/." "${OVERLAY_TARGET}/"

cd "${SDK_DIR}"

echo "Building the complete SDK image set"
./build.sh all

echo "Packaging update.img"
./build.sh updateimg

echo "Build complete: ${SDK_DIR}/output/image/update.img"
