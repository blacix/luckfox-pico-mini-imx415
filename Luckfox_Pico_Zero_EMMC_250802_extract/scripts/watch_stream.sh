#!/bin/bash
# watch_stream.sh -- answer "is it the board or is it my VLC?" from the workstation side,
# in one run. Nothing is installed on the board; this only reads the stream.
#
#       ./scripts/watch_stream.sh                     # against 10.15.116.182
#       BOARD=172.32.0.93 ./scripts/watch_stream.sh    # over the USB gadget link
#
# Two hard-won details are baked in. (1) Every probe is bounded, and none of them uses
# `-t N -f null -`: that form does not reliably terminate against this server (it can sit
# ESTABLISHED and idle forever), while `-t N -c copy -f h264 <file>` always returns. macOS
# ships no `timeout` binary, so bounds are explicit background-and-kill. (2) The path check
# asks the server directly instead of inferring it from a byte count, because a path can be
# accepted and still stream nothing -- /live/1 answers DESCRIBE 200 OK and never delivers a
# single byte, which a byte-count-only check misreports as "path refused".
BOARD=${BOARD:-10.15.116.182}
PORT=${PORT:-554}
URL="rtsp://$BOARD:$PORT/live/0"

echo "== 1. can I open a TCP socket to $BOARD:$PORT ? =="
if (exec 3<>"/dev/tcp/$BOARD/$PORT") 2>/dev/null; then
    echo "   yes -- rkipc's RTSP server is reachable"
else
    echo "   NO. Read your player's own wording, because the two cases differ:"
    echo "     'Connection refused' -> wrong IP, or rkipc is not running (on the board: pidof rkipc)"
    echo "     hangs / times out    -> no route from this host to $BOARD (different subnet, VPN,"
    echo "                             client isolation on the network, or a host firewall)"
    echo "   No VLC setting can fix that; fix the route first."
    exit 1
fi

echo "== 2. what does the server itself say about each path? =="
python3 - "$BOARD" "$PORT" <<'PY'
import socket, sys
host, port = sys.argv[1], int(sys.argv[2])
for path in ('/live/0', '/live/1', '/video/0', '/stream0', '/'):
    try:
        s = socket.create_connection((host, port), 4); s.settimeout(6)
        s.sendall(('DESCRIBE rtsp://%s:%d%s RTSP/1.0\r\nCSeq: 1\r\n'
                   'User-Agent: watch_stream\r\nAccept: application/sdp\r\n\r\n'
                   % (host, port, path)).encode())
        reply = s.recv(200).decode('utf8', 'replace').split('\r\n')[0]
        s.close()
    except Exception as exc:
        reply = 'no reply (%s)' % type(exc).__name__
    note = ''
    if '200' in reply:
        note = '  <- advertised but SILENT: never streams, VLC shows black' if path == '/live/1' \
             else ('  <- the one to use' if path == '/live/0' else '')
    elif '454' in reply:
        note = '  <- VLC: "VLC is unable to open the MRL ..."'
    print('   %-9s %s%s' % (path, reply, note))
PY

command -v ffprobe >/dev/null 2>&1 || { echo "   (ffmpeg/ffprobe missing, cannot measure delivery)"; exit 0; }

echo "== 3. what is being delivered on /live/0 right now? =="
# BSD/macOS mktemp needs the X's at the END of the template, so `watch.XXXXXX.h264` fails
# with "File exists" -- build the name from the pid instead, which is portable and unique.
TMP=/tmp/watch.$$
rm -f "$TMP"
ffmpeg -v error -rtsp_transport tcp -i "$URL" -t 6 -c copy -f h264 "$TMP" 2>/tmp/watch.err &
P=$!; N=0
while [ $N -lt 40 ]; do kill -0 $P 2>/dev/null || break; sleep 0.5; N=$((N + 1)); done
if kill -0 $P 2>/dev/null; then
    kill -9 $P 2>/dev/null; wait $P 2>/dev/null
    echo "   capture had to be killed at 20 s: the session was accepted but nothing streamed."
    echo "   On the board run:  /userdata/start_camera.sh"
    rm -f "$TMP"; exit 1
fi
BYTES=$(wc -c < "$TMP" | tr -d ' ')
FRAMES=$(ffprobe -v error -count_frames -select_streams v:0 -show_entries stream=nb_read_frames \
         -of default=nw=1:nk=1 "$TMP" 2>/dev/null)
if [ "${BYTES:-0}" -lt 1000 ]; then
    echo "   nothing usable arrived ($BYTES bytes) although the path was accepted. rkipc is"
    echo "   listening but has no live stream -- on the board run:  /userdata/start_camera.sh"
    [ -s /tmp/watch.err ] && { echo "   ffmpeg said:"; sed 's/^/     /' /tmp/watch.err | head -3; }
    rm -f "$TMP"; exit 1
fi
python3 - "${BYTES:-0}" "${FRAMES:-0}" <<'PY'
import sys
b, f = float(sys.argv[1]), float(sys.argv[2])
print('   %.0f kbps, %d frames in 6 s = %.1f fps' % (b * 8 / 6 / 1000, f, f / 6.0))
print('   healthy here = ~26-28 fps and 1.2-2.3 Mbps. The ini asks for 25 fps / 2048 kbps')
print('   CBR; the mode tops out near 27.7 fps and a still scene makes Rockchip undershoot')
print('   the bitrate, so both differences from the ini are normal, not faults.')
PY
rm -f "$TMP"

echo "== 4. then VLC should open exactly this =="
echo "     $URL"
echo "   Steps 1-3 passed, so if VLC still shows nothing, it is the player:"
echo "     * the path must be /live/0 -- not /video/0 or /stream0 or / (all 454), and not"
echo "       /live/1 (accepted, then black forever)"
echo "     * VLC defaults to UDP; force TCP: Tools > Preferences > Input / Codecs > Live555"
echo "       stream connection > TCP, or:  vlc --rtsp-tcp '$URL'"
echo "     * Tools > Messages (verbosity 2) prints the RTSP reply VLC really got, which names"
echo "       the cause: '454 Session Not Found' = path, 'connection error' = route."
echo "   Measured on this board: VLC 3.0.23 decodes it over TCP and UDP, six concurrent"
echo "   clients are all served, and a fresh client is served 2 s after six are SIGKILLed --"
echo "   so a leftover player is not locking you out."
