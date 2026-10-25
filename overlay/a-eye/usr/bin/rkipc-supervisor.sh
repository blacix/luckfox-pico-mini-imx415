#!/bin/sh

RKIPC=/oem/usr/bin/rkipc
INI=/usr/share/rkipc-imx415-720p.ini
IQ_DIR=/usr/share/iqfiles
IQ_FILE=${IQ_DIR}/imx415_CMK-OT2022-PX1_IR0147-36IRC-8M-F20.json
LOGFILE=/tmp/rkipc.log
RETRY_DELAY=5

child_pid=
timer_pid=
stopping=0

log() {
	printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOGFILE"
}

if [ ! -x "$RKIPC" ]; then
	echo "Missing rkipc executable: $RKIPC" >&2
	exit 1
fi
if [ ! -f "$INI" ]; then
	echo "Missing IMX415 rkipc profile: $INI" >&2
	exit 1
fi
if [ ! -f "$IQ_FILE" ]; then
	echo "Missing IMX415 IQ file: $IQ_FILE" >&2
	exit 1
fi

LD_LIBRARY_PATH="/oem/usr/lib:/oem/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export LD_LIBRARY_PATH

request_stop() {
	stopping=1
	if [ -n "$child_pid" ]; then
		kill -TERM "$child_pid" 2>/dev/null || true
	fi
	if [ -n "$timer_pid" ]; then
		kill -TERM "$timer_pid" 2>/dev/null || true
	fi
}

trap 'request_stop' TERM INT

while [ "$stopping" -eq 0 ]; do
	: >"$LOGFILE"
	log "Starting rkipc"
	"$RKIPC" -c "$INI" -a "$IQ_DIR" >>"$LOGFILE" 2>&1 &
	child_pid=$!
	wait "$child_pid"
	exit_status=$?
	child_pid=

	if [ "$stopping" -ne 0 ]; then
		break
	fi

	log "rkipc exited with status $exit_status; retrying in ${RETRY_DELAY}s"
	sleep "$RETRY_DELAY" &
	timer_pid=$!
	wait "$timer_pid"
	timer_pid=
done

log "rkipc supervisor stopped"
exit 0
