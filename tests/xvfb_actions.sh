#!/bin/sh
# An action button clicked with real X events, run inside xvfb-run by
# tests/run.sh:
#   tests/xvfb_actions.sh <file> <log> <controls>
# 640x480 window: the row's top is at y 418 (margins.bottom 62), so the
# button goes from y 370 to 406, its right edge at x 620. The cursor goes
# straight to it and clicks: the command must arrive once, and the script
# hides the button. A second click there, once mpv's double-click time is
# over, must find nothing. Then the script shows a button it never hides,
# in the same place: a double click on it must run its command once.
file=$1
log=$2
mpv --no-config --vo=x11 --ao=null --geometry=640x480+0+0 --pause --keep-open=yes \
    --script-opts-append=suji-controls="$3" \
    --script=./suji --script=tests/xvfb_actions.lua \
    --msg-level=all=no,suji=info,xvfb_actions=info "$file" >"$log" 2>&1 &
pid=$!
# Wait for the window and the button, at most 15 s.
wid=
for _ in $(seq 75); do
    wid=$(xdotool search --class mpv 2>/dev/null | head -1)
    [ -n "$wid" ] && grep -q '^\[xvfb_actions\] shown' "$log" && break
    wid=
    sleep 0.2
done
if [ -z "$wid" ]; then
    kill "$pid" 2>/dev/null
    exit 1
fi
sleep 0.5
xdotool mousemove --window "$wid" 600 388
sleep 0.5
xdotool click 1
sleep 1
xdotool click 1
for _ in $(seq 25); do
    grep -q '^\[xvfb_actions\] stay shown' "$log" && break
    sleep 0.2
done
sleep 0.5
xdotool click --repeat 2 --delay 100 1
sleep 1
kill "$pid" 2>/dev/null
wait "$pid" 2>/dev/null
exit 0
