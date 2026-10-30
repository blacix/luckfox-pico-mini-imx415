#!/usr/bin/env bash
set -euo pipefail

cd /workspace
./build.sh "$@"

mkdir -p /output
cp -- "${A_EYE_SDK_DIR}/output/image/update.img" /output/update.img
UPGRADE_TOOL_DIR="${A_EYE_SDK_DIR}/tools/linux/Linux_Upgrade_Tool"
mkdir -p /output/upgrade_tool
cp -- "${UPGRADE_TOOL_DIR}/upgrade_tool" \
    "${UPGRADE_TOOL_DIR}/config.ini" \
    "${UPGRADE_TOOL_DIR}/88-rockusb.rules" \
    /output/upgrade_tool/
chmod 0755 /output/upgrade_tool/upgrade_tool
chown -R "${HOST_UID:-1000}:${HOST_GID:-1000}" /output
echo "Host-visible firmware image: build/update.img"
echo "Host flashing tool: build/upgrade_tool/upgrade_tool"
