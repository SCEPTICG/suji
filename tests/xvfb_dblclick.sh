#!/bin/sh
# Double clicks with real X events, run inside xvfb-run by tests/run.sh:
#   tests/xvfb_dblclick.sh <file> <log>
# The file is the one of the menu test (640x480 window; the more button is
# at x 408-452, y 440; its "2x" entry at y 301). First a double click on that
# entry: it sets the speed and must not toggle fullscreen. Then, without
# moving, a double click on the video, once the menu is gone and mpv's
# double-click time is over: that one is mpv's and toggles fullscreen.
file=$1
log=$2
mpv --no-config --vo=x11 --ao=null --geometry=640x480+0+0 --pause --keep-open=yes \
    --script=./suji --script=tests/xvfb_dblclick.lua \
    --msg-level=all=no,suji=info,xvfb_dblclick=info "$file" >"$log" 2>&1 &
pid=$!
sleep 3
wid=$(xdotool search --class mpv | head -1)
if [ -z "$wid" ]; then
    kill "$pid" 2>/dev/null
    exit 1
fi
xdotool mousemove --window "$wid" 430 440
sleep 0.5
xdotool click 1 # opens the menu
sleep 0.6
xdotool mousemove --window "$wid" 448 301
sleep 0.5
xdotool click --repeat 2 --delay 250 1
sleep 2
xdotool click --repeat 2 --delay 100 1
sleep 1
kill "$pid" 2>/dev/null
wait "$pid" 2>/dev/null
exit 0
