#!/bin/sh
# Double clicks with real X events, run inside xvfb-run by tests/run.sh:
#   tests/xvfb_dblclick.sh <file> <log> <controls>
# The file is the one of the menu test and the row the one run.sh gives it
# (640x480 window; the speed button is at x 472-516, y 440; its "2x"
# entry, the eighth under the title, at y 307). First a double click on
# that entry: it sets the speed and must not toggle fullscreen. Then,
# without moving, a double click on the video, once the menu is gone and
# mpv's double-click time is over: that one is mpv's and toggles
# fullscreen.
file=$1
log=$2
mpv --no-config --vo=x11 --ao=null --geometry=640x480+0+0 --pause --keep-open=yes \
    --script-opts-append=suji-controls="$3" \
    --script=./suji --script=tests/xvfb_dblclick.lua \
    --msg-level=all=no,suji=info,xvfb_dblclick=info "$file" >"$log" 2>&1 &
pid=$!
# Wait for the window and for suji to start (it logs nothing without
# debug: the script below logs the speed at start), at most 15 s.
wid=
for _ in $(seq 75); do
    wid=$(xdotool search --class mpv 2>/dev/null | head -1)
    [ -n "$wid" ] && grep -q '^\[xvfb_dblclick\] speed' "$log" && break
    wid=
    sleep 0.2
done
if [ -z "$wid" ]; then
    kill "$pid" 2>/dev/null
    exit 1
fi
sleep 0.5
xdotool mousemove --window "$wid" 494 440
sleep 0.5
xdotool click 1 # opens the menu
sleep 0.6
xdotool mousemove --window "$wid" 512 307
sleep 0.5
xdotool click --repeat 2 --delay 250 1
sleep 2
xdotool click --repeat 2 --delay 100 1
sleep 1
kill "$pid" 2>/dev/null
wait "$pid" 2>/dev/null
exit 0
