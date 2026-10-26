#!/bin/sh

JPEG_APP=/usr/bin/night-vision-jpeg
IMX415_INIT=/etc/init.d/S99a-eye-cam
LED_DIR=/sys/class/leds/pwm0_led
GPIO_EXPORT=/sys/class/gpio/export
GPIO_DIR=/sys/class/gpio/gpio116
LOG_FILE=/tmp/night-vision.log
CONFIG_FILE=/etc/default/a-eye-night-vision
NIGHT_ON_THRESHOLD=80
DAY_ON_THRESHOLD=85
DAY_P90_MIN=120
DAY_P90_MAX=135
INTERVAL_SECONDS=5
SWITCH_SAMPLES_REQUIRED=2

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
if ! awk -v minimum="$DAY_P90_MIN" -v maximum="$DAY_P90_MAX" \
	'BEGIN { exit !(minimum >= 0 && maximum <= 255 && minimum < maximum) }'; then
	log 'DAY_P90_MIN and DAY_P90_MAX must define an increasing range within 0..255'
	exit 1
fi
case "$SWITCH_SAMPLES_REQUIRED" in
	''|*[!0-9]*) log 'SWITCH_SAMPLES_REQUIRED must be an integer from 1 to 100'; exit 1 ;;
esac
if [ "$SWITCH_SAMPLES_REQUIRED" -lt 1 ] ||
	[ "$SWITCH_SAMPLES_REQUIRED" -gt 100 ]; then
	log 'SWITCH_SAMPLES_REQUIRED must be an integer from 1 to 100'
	exit 1
fi
LED_NIGHT_BRIGHTNESS=$((LED_MAX / 2))

write_value "$LED_DIR/brightness" 0
if [ "$SHUTTER_CONTROL" -eq 1 ]; then
	sleep 1
	write_value "$GPIO_DIR/value" 1
	log "monitoring mean_y; night below ${NIGHT_ON_THRESHOLD}, day above ${DAY_ON_THRESHOLD} with p90_y in [${DAY_P90_MIN}, ${DAY_P90_MAX}]; ${SWITCH_SAMPLES_REQUIRED} consecutive samples required; shutter control enabled"
else
	log "monitoring mean_y; night below ${NIGHT_ON_THRESHOLD}, day above ${DAY_ON_THRESHOLD} with p90_y in [${DAY_P90_MIN}, ${DAY_P90_MAX}]; ${SWITCH_SAMPLES_REQUIRED} consecutive samples required; LED-only mode (SC3336)"
fi
mode=day
last_error=
night_candidate_count=0
day_candidate_count=0

while :; do
	if SAMPLE_OUTPUT=$("$JPEG_APP" 2>&1); then
		MEAN_Y=$(printf '%s\n' "$SAMPLE_OUTPUT" | sed -n 's/.*"mean_y":[[:space:]]*\([0-9][0-9.]*\).*/\1/p' | sed -n '1p')
		P90_Y=$(printf '%s\n' "$SAMPLE_OUTPUT" | sed -n 's/.*"p90_y":[[:space:]]*\([0-9][0-9.]*\).*/\1/p' | sed -n '1p')
		if ! awk -v mean="$MEAN_Y" -v p90="$P90_Y" \
			'BEGIN { exit !(mean ~ /^[0-9]+([.][0-9]+)?$/ && mean >= 0 && mean <= 255 && p90 ~ /^[0-9]+([.][0-9]+)?$/ && p90 >= 0 && p90 <= 255) }'; then
			ERROR='invalid mean_y or p90_y output from JPEG image processor'
		else
			ERROR=
		fi
	else
		ERROR='JPEG image processor failed'
	fi

	if [ -n "$ERROR" ]; then
		night_candidate_count=0
		day_candidate_count=0
		if [ "$ERROR" != "$last_error" ]; then
			log "$ERROR"
			last_error=$ERROR
		fi
	else
		if [ -n "$last_error" ]; then
			log 'JPEG brightness sampling recovered'
			last_error=
		fi
		if [ "$mode" = day ]; then
			day_candidate_count=0
			if awk -v mean="$MEAN_Y" -v threshold="$NIGHT_ON_THRESHOLD" \
				'BEGIN { exit !(mean < threshold) }'; then
				night_candidate_count=$((night_candidate_count + 1))
			else
				night_candidate_count=0
			fi
			if [ "$night_candidate_count" -ge "$SWITCH_SAMPLES_REQUIRED" ]; then
				if [ "$SHUTTER_CONTROL" -eq 1 ]; then
					write_value "$GPIO_DIR/value" 0
					sleep 1
				fi
				write_value "$LED_DIR/brightness" "$LED_NIGHT_BRIGHTNESS"
				mode=night
				night_candidate_count=0
				if [ "$SHUTTER_CONTROL" -eq 1 ]; then
					log "night mode: shutter low, IR LED brightness ${LED_NIGHT_BRIGHTNESS}/${LED_MAX}"
				else
					log "night mode: shutter unchanged, IR LED brightness ${LED_NIGHT_BRIGHTNESS}/${LED_MAX}"
				fi
			fi
		else
			night_candidate_count=0
			if awk \
				-v mean="$MEAN_Y" \
				-v threshold="$DAY_ON_THRESHOLD" \
				-v p90="$P90_Y" \
				-v p90_min="$DAY_P90_MIN" \
				-v p90_max="$DAY_P90_MAX" \
				'BEGIN { exit !(mean > threshold && p90 >= p90_min && p90 <= p90_max) }'; then
				day_candidate_count=$((day_candidate_count + 1))
			else
				day_candidate_count=0
			fi
			if [ "$day_candidate_count" -ge "$SWITCH_SAMPLES_REQUIRED" ]; then
				write_value "$LED_DIR/brightness" 0
				if [ "$SHUTTER_CONTROL" -eq 1 ]; then
					sleep 1
					write_value "$GPIO_DIR/value" 1
				fi
				mode=day
				day_candidate_count=0
				if [ "$SHUTTER_CONTROL" -eq 1 ]; then
					log 'day mode: shutter high, IR LED off'
				else
					log 'day mode: shutter unchanged, IR LED off'
				fi
			fi
		fi
	fi

	sleep "$INTERVAL_SECONDS"
done
