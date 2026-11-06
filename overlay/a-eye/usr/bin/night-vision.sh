#!/bin/sh

MEASUREMENT_APP=/usr/bin/night-vision-measurement
IMX415_INIT=/etc/init.d/S99a-eye-cam
LED_DIR=/sys/class/leds/pwm0_led
GPIO_EXPORT=/sys/class/gpio/export
GPIO_DIR=/sys/class/gpio/gpio116
LOG_FILE=/tmp/night-vision.log
CONFIG_FILE=/etc/default/a-eye-night-vision
NIGHT_ON_THRESHOLD=75
DAY_ON_THRESHOLD=75
DAY_P90_MIN=110
DAY_P90_MAX=210
NIGHT_LED_MEAN_COMPENSATION=20
INTERVAL_SECONDS=2
MODE_SETTLE_SECONDS=10
SWITCH_SAMPLES_REQUIRED=2
LED_INTENSITY_PERCENT=10
MEASUREMENT_METHOD=v4l2
V4L2_DEVICE=
V4L2_NIGHT_ON_THRESHOLD=100
V4L2_DAY_ON_THRESHOLD=500
V4L2_LED_COMPENSATION=0
NIGHT_EXPOSURE_THRESHOLD_SECONDS=0
DAY_GAIN_MAX=0
V4L2_CTL=/usr/bin/v4l2-ctl

if [ -r "$CONFIG_FILE" ]; then
	. "$CONFIG_FILE"
fi

log() {
	printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"
}

write_value() {
	printf '%s\n' "$2" > "$1"
}

read_v4l2_sample() {
	V4L2_NODE=$V4L2_DEVICE
	V4L2_SENSOR=
	if [ -n "$V4L2_NODE" ]; then
		V4L2_NAME_FILE="/sys/class/video4linux/${V4L2_NODE##*/}/name"
		if [ -r "$V4L2_NAME_FILE" ]; then
			V4L2_SENSOR=$(cat "$V4L2_NAME_FILE")
		fi
	else
		for V4L2_ENTRY in /sys/class/video4linux/v4l-subdev*; do
			[ -r "$V4L2_ENTRY/name" ] || continue
			V4L2_NAME=$(cat "$V4L2_ENTRY/name")
			case "$V4L2_NAME" in
				*sc3336*|*imx415*)
					V4L2_NODE="/dev/${V4L2_ENTRY##*/}"
					V4L2_SENSOR=$V4L2_NAME
					break
					;;
			esac
		done
	fi
	if [ -z "$V4L2_NODE" ] || [ -z "$V4L2_SENSOR" ]; then
		ERROR='no named SC3336 or IMX415 V4L2 subdevice found'
		return 1
	fi
	case "$V4L2_SENSOR" in
		*sc3336*) V4L2_SENSOR_KIND=sc3336 ;;
		*imx415*) V4L2_SENSOR_KIND=imx415 ;;
		*) ERROR="unsupported V4L2 sensor: $V4L2_SENSOR"; return 1 ;;
	esac
	V4L2_CONTROLS=$($V4L2_CTL -d "$V4L2_NODE" \
		--get-ctrl=exposure,analogue_gain,pixel_rate,horizontal_blanking 2>&1) || {
		ERROR="v4l2-ctl failed for $V4L2_NODE: $V4L2_CONTROLS"
		return 1
	}
	V4L2_EXPOSURE_RAW=$(printf '%s\n' "$V4L2_CONTROLS" | sed -n 's/^exposure:[[:space:]]*//p' | sed -n '1p')
	V4L2_GAIN_RAW=$(printf '%s\n' "$V4L2_CONTROLS" | sed -n 's/^analogue_gain:[[:space:]]*//p' | sed -n '1p')
	V4L2_PIXEL_RATE=$(printf '%s\n' "$V4L2_CONTROLS" | sed -n 's/^pixel_rate:[[:space:]]*//p' | sed -n '1p')
	V4L2_HBLANK=$(printf '%s\n' "$V4L2_CONTROLS" | sed -n 's/^horizontal_blanking:[[:space:]]*//p' | sed -n '1p')
	case "$V4L2_SENSOR_KIND" in
		sc3336) V4L2_SENSOR_WIDTH=2304 ;;
		imx415) V4L2_SENSOR_WIDTH=1944 ;;
	esac
	V4L2_DERIVED=$(awk \
		-v sensor="$V4L2_SENSOR_KIND" \
		-v exposure="$V4L2_EXPOSURE_RAW" \
		-v gain_raw="$V4L2_GAIN_RAW" \
		-v pixel_rate="$V4L2_PIXEL_RATE" \
		-v hblank="$V4L2_HBLANK" \
		-v width="$V4L2_SENSOR_WIDTH" \
		'BEGIN {
			if (exposure !~ /^[0-9]+([.][0-9]+)?$/ ||
			    gain_raw !~ /^[0-9]+([.][0-9]+)?$/ ||
			    pixel_rate !~ /^[0-9]+([.][0-9]+)?$/ ||
			    hblank !~ /^[0-9]+([.][0-9]+)?$/ || pixel_rate <= 0) exit 1
			if (sensor == "sc3336") {
				exposure_seconds = (exposure / 16) * (width + hblank) / pixel_rate
				gain = gain_raw / 128
			} else {
				if (gain_raw >= 256) exit 1
				exposure_seconds = exposure * (width + hblank) / pixel_rate
				gain = 256 / (256 - gain_raw)
			}
			if (exposure_seconds <= 0 || gain <= 0) exit 1
			score = 2.55 / (exposure_seconds * gain)
			printf "%.9f %.9f %.9f\n", exposure_seconds, gain, score
		}') || {
		ERROR="invalid exposure/gain controls from $V4L2_NODE"
		return 1
	}
	set -- $V4L2_DERIVED
	V4L2_EXPOSURE_SECONDS=$1
	V4L2_LINEAR_GAIN=$2
	V4L2_SCORE=$3
	ERROR=
	return 0
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
case "$MEASUREMENT_METHOD" in
	jpeg)
		if [ ! -x "$MEASUREMENT_APP" ]; then
			log "missing JPEG measurement executable: $MEASUREMENT_APP"
			exit 1
		fi
		;;
	v4l2)
		if [ ! -x "$V4L2_CTL" ]; then
			log "missing V4L2 control tool: $V4L2_CTL"
			exit 1
		fi
		;;
	*)
		log "unsupported MEASUREMENT_METHOD: $MEASUREMENT_METHOD (expected jpeg or v4l2)"
		exit 1
		;;
esac
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
if [ "$MEASUREMENT_METHOD" = jpeg ]; then
	if ! awk -v minimum="$DAY_P90_MIN" -v maximum="$DAY_P90_MAX" \
		'BEGIN { exit !(minimum >= 0 && maximum <= 255 && minimum < maximum) }'; then
		log 'DAY_P90_MIN and DAY_P90_MAX must define an increasing range within 0..255'
		exit 1
	fi
	if ! awk -v compensation="$NIGHT_LED_MEAN_COMPENSATION" \
		'BEGIN { exit !(compensation ~ /^[0-9]+([.][0-9]+)?$/ && compensation >= 0 && compensation <= 255) }'; then
		log 'NIGHT_LED_MEAN_COMPENSATION must be a number from 0 to 255'
		exit 1
	fi
	if ! awk -v night="$NIGHT_ON_THRESHOLD" -v day="$DAY_ON_THRESHOLD" \
		-v compensation="$NIGHT_LED_MEAN_COMPENSATION" \
		'BEGIN { exit !(night >= 0 && night <= 255 && day >= 0 && day <= 255 && day + compensation > night) }'; then
		log 'the effective JPEG day-return threshold (DAY_ON_THRESHOLD plus LED compensation) must exceed NIGHT_ON_THRESHOLD'
		exit 1
	fi
else
	if ! awk -v night="$V4L2_NIGHT_ON_THRESHOLD" \
		-v day="$V4L2_DAY_ON_THRESHOLD" \
		-v compensation="$V4L2_LED_COMPENSATION" \
		-v exposure="$NIGHT_EXPOSURE_THRESHOLD_SECONDS" \
		-v gain="$DAY_GAIN_MAX" \
		'BEGIN {
			if (night !~ /^[0-9]+([.][0-9]+)?$/ || day !~ /^[0-9]+([.][0-9]+)?$/ ||
			    compensation !~ /^[0-9]+([.][0-9]+)?$/ ||
			    exposure !~ /^[0-9]+([.][0-9]+)?$/ || gain !~ /^[0-9]+([.][0-9]+)?$/) exit 1
			exit !(night >= 0 && day >= 0 && compensation >= 0 &&
			       night < day + compensation && exposure >= 0 && gain >= 0)
		}'; then
		log 'V4L2 thresholds, compensation, and optional triggers must be nonnegative numbers with night below day plus compensation'
		exit 1
	fi
fi
case "$SWITCH_SAMPLES_REQUIRED" in
	''|*[!0-9]*) log 'SWITCH_SAMPLES_REQUIRED must be an integer from 1 to 100'; exit 1 ;;
esac
if [ "$SWITCH_SAMPLES_REQUIRED" -lt 1 ] ||
	[ "$SWITCH_SAMPLES_REQUIRED" -gt 100 ]; then
	log 'SWITCH_SAMPLES_REQUIRED must be an integer from 1 to 100'
	exit 1
fi
case "$MODE_SETTLE_SECONDS" in
	''|*[!0-9]*) log 'MODE_SETTLE_SECONDS must be an integer from 0 to 3600'; exit 1 ;;
esac
if [ "$MODE_SETTLE_SECONDS" -gt 3600 ]; then
	log 'MODE_SETTLE_SECONDS must be an integer from 0 to 3600'
	exit 1
fi
case "$LED_INTENSITY_PERCENT" in
	''|*[!0-9]*) log 'LED_INTENSITY_PERCENT must be an integer from 0 to 100'; exit 1 ;;
esac
if [ "$LED_INTENSITY_PERCENT" -gt 100 ]; then
	log 'LED_INTENSITY_PERCENT must be an integer from 0 to 100'
	exit 1
fi
LED_NIGHT_BRIGHTNESS=$(((LED_MAX * LED_INTENSITY_PERCENT + 50) / 100))

write_value "$LED_DIR/brightness" 0
if [ "$SHUTTER_CONTROL" -eq 1 ]; then
	sleep 1
	write_value "$GPIO_DIR/value" 1
	SHUTTER_DESCRIPTION='shutter control enabled'
else
	SHUTTER_DESCRIPTION='LED-only mode (SC3336); shutter unchanged'
fi
if [ "$MEASUREMENT_METHOD" = v4l2 ]; then
	log "measurement method v4l2; monitoring sensor exposure/gain every ${INTERVAL_SECONDS}s; night below ${V4L2_NIGHT_ON_THRESHOLD}, day above ${V4L2_DAY_ON_THRESHOLD} with V4L2 LED score compensation ${V4L2_LED_COMPENSATION}; ${SWITCH_SAMPLES_REQUIRED} consecutive samples required; ${MODE_SETTLE_SECONDS}s mode settle; LED intensity ${LED_INTENSITY_PERCENT}% (${LED_NIGHT_BRIGHTNESS}/${LED_MAX}); ${SHUTTER_DESCRIPTION}"
else
	log "measurement method jpeg; monitoring mean_y every ${INTERVAL_SECONDS}s; night below ${NIGHT_ON_THRESHOLD}, day above ${DAY_ON_THRESHOLD} after ${NIGHT_LED_MEAN_COMPENSATION} mean_y LED compensation with p90_y in [${DAY_P90_MIN}, ${DAY_P90_MAX}]; ${SWITCH_SAMPLES_REQUIRED} consecutive samples required; ${MODE_SETTLE_SECONDS}s mode settle; LED intensity ${LED_INTENSITY_PERCENT}% (${LED_NIGHT_BRIGHTNESS}/${LED_MAX}); ${SHUTTER_DESCRIPTION}"
fi
mode=day
last_error=
night_candidate_count=0
day_candidate_count=0

while :; do
	mode_changed=0
	if [ "$MEASUREMENT_METHOD" = v4l2 ]; then
		read_v4l2_sample || true
	else
		if SAMPLE_OUTPUT=$("$MEASUREMENT_APP" 2>&1); then
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
			log "${MEASUREMENT_METHOD} sampling recovered"
			last_error=
		fi
		if [ "$mode" = day ]; then
			day_candidate_count=0
			if [ "$MEASUREMENT_METHOD" = v4l2 ]; then
				NIGHT_SAMPLE=$(awk -v score="$V4L2_SCORE" \
					-v threshold="$V4L2_NIGHT_ON_THRESHOLD" \
					-v exposure="$V4L2_EXPOSURE_SECONDS" \
					-v exposure_threshold="$NIGHT_EXPOSURE_THRESHOLD_SECONDS" \
					'BEGIN { exit !(score < threshold || (exposure_threshold > 0 && exposure >= exposure_threshold)) }' && echo yes || echo no)
			else
				NIGHT_SAMPLE=$(awk -v mean="$MEAN_Y" -v threshold="$NIGHT_ON_THRESHOLD" \
					'BEGIN { exit !(mean < threshold) }' && echo yes || echo no)
			fi
			if [ "$NIGHT_SAMPLE" = yes ]; then
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
				mode_changed=1
				night_candidate_count=0
				if [ "$SHUTTER_CONTROL" -eq 1 ]; then
					log "night mode: shutter low, IR LED brightness ${LED_NIGHT_BRIGHTNESS}/${LED_MAX}"
				else
					log "night mode: shutter unchanged, IR LED brightness ${LED_NIGHT_BRIGHTNESS}/${LED_MAX}"
				fi
			fi
		else
			night_candidate_count=0
			if [ "$MEASUREMENT_METHOD" = v4l2 ]; then
				DAY_SAMPLE=$(awk -v score="$V4L2_SCORE" \
					-v led_compensation="$V4L2_LED_COMPENSATION" \
					-v threshold="$V4L2_DAY_ON_THRESHOLD" \
					-v gain="$V4L2_LINEAR_GAIN" \
					-v gain_threshold="$DAY_GAIN_MAX" \
					'BEGIN { exit !(score - led_compensation > threshold || (gain_threshold > 0 && gain < gain_threshold)) }' && echo yes || echo no)
			else
				DAY_SAMPLE=$(awk \
					-v mean="$MEAN_Y" \
					-v led_compensation="$NIGHT_LED_MEAN_COMPENSATION" \
					-v threshold="$DAY_ON_THRESHOLD" \
					-v p90="$P90_Y" \
					-v p90_min="$DAY_P90_MIN" \
					-v p90_max="$DAY_P90_MAX" \
					'BEGIN { exit !(mean - led_compensation > threshold && p90 >= p90_min && p90 <= p90_max) }' && echo yes || echo no)
			fi
			if [ "$DAY_SAMPLE" = yes ]; then
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
				mode_changed=1
				day_candidate_count=0
				if [ "$SHUTTER_CONTROL" -eq 1 ]; then
					log 'day mode: shutter high, IR LED off'
				else
					log 'day mode: shutter unchanged, IR LED off'
				fi
			fi
		fi
	fi

	if [ "$mode_changed" -eq 1 ]; then
		sleep "$MODE_SETTLE_SECONDS"
	else
		sleep "$INTERVAL_SECONDS"
	fi
done
