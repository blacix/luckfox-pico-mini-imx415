#!/bin/sh

JPEG_APP=/usr/bin/night-vision-jpeg
IMX415_INIT=/etc/init.d/S99a-eye-cam
LED_DIR=/sys/class/leds/pwm0_led
GPIO_EXPORT=/sys/class/gpio/export
GPIO_DIR=/sys/class/gpio/gpio116
LOG_FILE=/tmp/night-vision.log
CONFIG_FILE=/etc/default/a-eye-night-vision
NIGHT_ON_THRESHOLD=80
DAY_ON_THRESHOLD=95
INTERVAL_SECONDS=3

if [ -r "$CONFIG_FILE" ]; then
	. "$CONFIG_FILE"
fi

log() {
	printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"
}

write_value() {
	printf '%s\n' "$2" > "$1"
}

cleanup() {
	[ ! -w "$LED_DIR/brightness" ] || write_value "$LED_DIR/brightness" 0
	if [ "$SHUTTER_CONTROL" -eq 1 ]; then
		[ ! -w "$GPIO_DIR/value" ] || write_value "$GPIO_DIR/value" 1
		log 'stopped: shutter high and IR LED off'
	else
		log 'stopped: IR LED off; shutter unchanged'
	fi
}

on_exit() {
	cleanup
}
trap on_exit EXIT
trap 'exit 0' INT TERM

SHUTTER_CONTROL=0
if [ -x "$IMX415_INIT" ]; then
	SHUTTER_CONTROL=1
fi

: > "$LOG_FILE"
if [ ! -x "$JPEG_APP" ]; then
	log "missing JPEG image processor: $JPEG_APP"
	exit 1
fi
if [ ! -r "$LED_DIR/max_brightness" ] || [ ! -w "$LED_DIR/brightness" ]; then
	log 'PWM LED interface is unavailable'
	exit 1
fi

if [ "$SHUTTER_CONTROL" -eq 1 ]; then
	if [ ! -d "$GPIO_DIR" ]; then
		write_value "$GPIO_EXPORT" 116 2>/dev/null || true
		i=0
		while [ ! -d "$GPIO_DIR" ] && [ "$i" -lt 10 ]; do
			sleep 0.1
			i=$((i + 1))
		done
	fi
	if [ ! -d "$GPIO_DIR" ] || ! write_value "$GPIO_DIR/direction" out; then
		log 'GPIO116 is unavailable or could not be configured as output'
		exit 1
	fi
fi

LED_MAX=$(cat "$LED_DIR/max_brightness")
case "$LED_MAX" in
	''|*[!0-9]*) log 'PWM LED maximum brightness is invalid'; exit 1 ;;
esac
if [ "$LED_MAX" -le 0 ]; then
	log 'PWM LED maximum brightness must be positive'
	exit 1
fi
LED_NIGHT_BRIGHTNESS=$((LED_MAX / 2))

write_value "$LED_DIR/brightness" 0
if [ "$SHUTTER_CONTROL" -eq 1 ]; then
	sleep 1
	write_value "$GPIO_DIR/value" 1
	log "monitoring mean_y; night below ${NIGHT_ON_THRESHOLD}, day above ${DAY_ON_THRESHOLD}; shutter control enabled"
else
	log "monitoring mean_y; night below ${NIGHT_ON_THRESHOLD}, day above ${DAY_ON_THRESHOLD}; LED-only mode (SC3336)"
fi
mode=day
last_error=

while :; do
	if SAMPLE_OUTPUT=$("$JPEG_APP" 2>&1); then
		MEAN_Y=$(printf '%s\n' "$SAMPLE_OUTPUT" | sed -n 's/.*"mean_y":[[:space:]]*\([0-9][0-9.]*\).*/\1/p' | sed -n '1p')
		if ! awk -v value="$MEAN_Y" 'BEGIN { exit !(value ~ /^[0-9]+([.][0-9]+)?$/ && value >= 0 && value <= 255) }'; then
			ERROR='invalid mean_y output from JPEG image processor'
		else
			ERROR=
		fi
	else
		ERROR='JPEG image processor failed'
	fi

	if [ -n "$ERROR" ]; then
		if [ "$ERROR" != "$last_error" ]; then
			log "$ERROR"
			last_error=$ERROR
		fi
	else
		if [ -n "$last_error" ]; then
			log 'JPEG brightness sampling recovered'
			last_error=
		fi
		if [ "$mode" = day ] && awk -v mean="$MEAN_Y" -v threshold="$NIGHT_ON_THRESHOLD" 'BEGIN { exit !(mean < threshold) }'; then
			if [ "$SHUTTER_CONTROL" -eq 1 ]; then
				write_value "$GPIO_DIR/value" 0
				sleep 1
			fi
			write_value "$LED_DIR/brightness" "$LED_NIGHT_BRIGHTNESS"
			mode=night
			if [ "$SHUTTER_CONTROL" -eq 1 ]; then
				log "night mode: shutter low, IR LED brightness ${LED_NIGHT_BRIGHTNESS}/${LED_MAX}"
			else
				log "night mode: shutter unchanged, IR LED brightness ${LED_NIGHT_BRIGHTNESS}/${LED_MAX}"
			fi
		elif [ "$mode" = night ] && awk -v mean="$MEAN_Y" -v threshold="$DAY_ON_THRESHOLD" 'BEGIN { exit !(mean > threshold) }'; then
			write_value "$LED_DIR/brightness" 0
			if [ "$SHUTTER_CONTROL" -eq 1 ]; then
				sleep 1
				write_value "$GPIO_DIR/value" 1
			fi
			mode=day
			if [ "$SHUTTER_CONTROL" -eq 1 ]; then
				log 'day mode: shutter high, IR LED off'
			else
				log 'day mode: shutter unchanged, IR LED off'
			fi
		fi
	fi

	sleep "$INTERVAL_SECONDS"
done
