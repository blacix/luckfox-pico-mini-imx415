#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat >&2 <<'EOF'
Usage: capture-rkipc-jpeg-adb.sh OUTPUT.jpg [ADB_SERIAL]

Ask the running RKIPC service for a JPEG, then pull its newest snapshot from
/userdata/video0 with adb. The script does not change camera, IR-cut, or LED
state; set those explicitly before each capture.
EOF
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
	usage
	exit 2
fi

output_path=$1
adb_bin=${ADB:-adb}
remote_dir=/userdata/video0

adb_args=()
if [[ $# -eq 2 ]]; then
	adb_args=(-s "$2")
fi

if ! "$adb_bin" "${adb_args[@]}" get-state >/dev/null 2>&1; then
	echo "No adb device is available" >&2
	exit 1
fi

output_dir=$(dirname -- "$output_path")
mkdir -p -- "$output_dir"

echo "Requesting a JPEG through RKIPC..." >&2
"$adb_bin" "${adb_args[@]}" shell /usr/bin/night-vision-measurement --keep-snapshots

remote_path=$("$adb_bin" "${adb_args[@]}" shell \
	"ls -1t ${remote_dir}/*.jpeg ${remote_dir}/*.jpg 2>/dev/null | head -n 1" |
	tr -d '\r')
if [[ -z "$remote_path" ]]; then
	echo "No JPEG snapshot found in ${remote_dir}" >&2
	exit 1
fi

echo "Pulling ${remote_path} to ${output_path}" >&2
"$adb_bin" "${adb_args[@]}" pull "$remote_path" "$output_path" >/dev/null
[[ -s "$output_path" ]] || {
	echo "Pulled JPEG is empty: ${output_path}" >&2
	exit 1
}
echo "$output_path"
