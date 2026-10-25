#!/usr/bin/env bash

set -euo pipefail

run_test() {
    local led=/sys/class/leds/pwm0_led

    if [[ ! -d "$led" ]]; then
        echo "Missing ${led}; boot firmware with the pwm-leds device-tree consumer first." >&2
        exit 1
    fi

    local max
    local low
    local mid
    max=$(cat "$led/max_brightness")
    max=$((max / 2))
    low=$((max / 4))
    mid=$((max / 2))

    cleanup() {
        echo 0 > /sys/class/leds/pwm0_led/brightness 2>/dev/null || true
    }

    trap cleanup EXIT
    trap 'exit 0' INT TERM

    while true; do
        for brightness in 0 "$low" "$mid" "$max" "$mid" "$low"; do
            echo "$brightness" > "$led/brightness"
            sleep 0.3
        done
    done
}

run_test
