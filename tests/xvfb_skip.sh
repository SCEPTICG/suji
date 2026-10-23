#!/bin/sh
# A double click on prev with real X events, run inside xvfb-run by
# tests/run.sh:
#   tests/xvfb_skip.sh <file> <log>
# Three entries of the same file, from the second, and the row
# pause,prev,next (640x480 window: prev at x 72-116, y 440). The first
# click goes back to the first entry, where prev hides and next takes its
# place: the second click must run nothing, nor toggle fullscreen.
file=$1
log=$2
mpv --no-config --vo=x11 --ao=null --geometry=640x480+0+0 --pause --keep-open=yes \
    --playlist-start=1 --script-opts-append=suji-controls=pause,prev,next \
    --script=./suji --script=tests/xvfb_dblclick.lua \
    --msg-level=all=no,suji=info,xvfb_dblclick=info "$file" "$file" "$file" >"$log" 2>&1 &
pid=$!
# Wait for the window and for suji to start, at most 15 s.
wid=
for _ in $(seq 75); do
    wid=$(xdotool search --class mpv 2>/dev/null | head -1)
    [ -n "$wid" ] && grep -q '^\[xvfb_dblclick\] playlist-pos 1 ' "$log" && break
    wid=
    sleep 0.2
done
if [ -z "$wid" ]; then
    kill "$pid" 2>/dev/null
    exit 1
fi
sleep 0.5
xdotool mousemove --window "$wid" 94 440
sleep 0.5
xdotool click --repeat 2 --delay 100 1
sleep 2
kill "$pid" 2>/dev/null
wait "$pid" 2>/dev/null
exit 0
