#!/bin/sh
# Runs the unit tests with Lua 5.1 (or $LUA), a smoke test with a windowless
# mpv and, if xvfb-run is installed, a real drag and click test, a test of
# the messages other scripts send, a menu test (which also needs ffmpeg and
# mkvmerge), a double click test and an action button test (which also
# need xdotool) in a virtual display.
# Usage: tests/run.sh   (from anywhere; needs lua5.1, mpv is optional)
set -u
cd "$(dirname "$0")/.." || exit 1
LUA=${LUA:-lua5.1}
export LUA_PATH="./suji/?.lua;./tests/?.lua;;"
status=0
tmp=
# Each test in a virtual display fixes its row, so its coordinates hold
# whatever the mpv: without a clipboard (0.39) the more button hides.
MENU_ROW=pause,time,space,subtitles,audio,playlist,speed,volume,fullscreen

for t in tests/test_*.lua; do
    "$LUA" "$t" || status=1
done

if ! command -v mpv >/dev/null 2>&1; then
    echo "smoke: skipped (no mpv)"
    echo "xvfb-drag: skipped (no mpv)"
    exit $status
fi

# Only suji's own lines count: errors and warnings from suji or from Lua.
# mpv's OSC is left on: suji has to turn it off by itself.
out=$(timeout 60 mpv --no-config --vo=null --ao=null --script=./suji \
    --script=tests/smoke_title.lua --script-opts=suji-debug=yes --length=5 \
    --msg-level=all=no,suji=info,smoke_title=info \
    'av://lavfi:testsrc=duration=10' 2>&1)
rc=$?
if printf '%s\n' "$out" | grep '^\[suji\]' | grep -qiE 'error|warn|traceback'; then
    printf 'smoke: FAIL\n%s\n' "$out"
    status=1
elif [ "$rc" -ne 0 ]; then
    printf 'smoke: FAIL (exit code %s)\n%s\n' "$rc" "$out"
    status=1
elif ! printf '%s\n' "$out" | grep -q '^\[suji\] start:'; then
    printf 'smoke: FAIL (suji did not start)\n%s\n' "$out"
    status=1
elif ! printf '%s\n' "$out" | grep -q '^\[suji\] set-title: Show / Episode'; then
    printf 'smoke: FAIL (no answer to set-title)\n%s\n' "$out"
    status=1
elif ! printf '%s\n' "$out" | grep -q '^\[smoke_title\] osc at start: no'; then
    printf 'smoke: FAIL (the OSC was not turned off)\n%s\n' "$out"
    status=1
elif ! printf '%s\n' "$out" | grep -q '^\[suji\] options: .*scale 1\.500'; then
    printf 'smoke: FAIL (scale not changed at run time)\n%s\n' "$out"
    status=1
elif ! printf '%s\n' "$out" | grep -q '^\[suji\] disabled' ||
     ! printf '%s\n' "$out" | grep -q '^\[smoke_title\] osc when disabled: yes'; then
    printf 'smoke: FAIL (enabled=no at run time)\n%s\n' "$out"
    status=1
else
    echo "smoke: ok"
fi

if command -v xvfb-run >/dev/null 2>&1; then
    tmp=$(mktemp -d) || exit 1
    trap 'rm -rf "$tmp"' EXIT
    trap 'exit 1' INT TERM HUP # exit, so the EXIT trap cleans up
    # A file with a fixed 60 s duration (lavfi sources grow while playing).
    timeout 120 mpv --no-config --really-quiet --o="$tmp/t.mkv" --ovc=mpeg4 \
        'av://lavfi:testsrc=duration=60:size=320x240:rate=10' >/dev/null 2>&1
fi
if [ -z "$tmp" ]; then
    echo "xvfb-drag: skipped (no xvfb-run)"
elif [ ! -s "$tmp/t.mkv" ]; then
    echo "xvfb-drag: skipped (could not make the test video)"
else
    out=$(timeout 60 xvfb-run -a mpv --no-config --vo=x11 --ao=null \
        --geometry=640x480 --pause --keep-open=yes --script=./suji \
        --script=tests/xvfb_drag.lua --script-opts=suji-debug=yes \
        --script-opts-append=suji-controls=pause,time,space,volume,fullscreen \
        --msg-level=all=no,suji=info,xvfb_drag=info \
        "$tmp/t.mkv" 2>&1)
    rc=$?
    if printf '%s\n' "$out" | grep '^\[suji\]' | grep -qiE 'error|warn|traceback'; then
        printf 'xvfb-drag: FAIL\n%s\n' "$out"
        status=1
    elif [ "$rc" -ne 0 ]; then
        printf 'xvfb-drag: FAIL (exit code %s)\n%s\n' "$rc" "$out"
        status=1
    elif ! printf '%s\n' "$out" | grep -q '^\[suji\] remaining time on'; then
        printf 'xvfb-drag: FAIL (click on the time)\n%s\n' "$out"
        status=1
    elif printf '%s\n' "$out" | grep -q 'xvfb-drag: ok'; then
        printf '%s\n' "$out" | grep 'xvfb-drag:'
    else
        printf 'xvfb-drag: FAIL\n%s\n' "$out"
        status=1
    fi
fi

# Messages from another script that behaves like hikari: loaded first, so
# it hears suji-version.
if [ -z "$tmp" ]; then
    echo "xvfb-api: skipped (no xvfb-run)"
elif [ ! -s "$tmp/t.mkv" ]; then
    echo "xvfb-api: skipped (could not make the test video)"
else
    out=$(timeout 60 xvfb-run -a mpv --no-config --vo=x11 --ao=null \
        --geometry=640x480 --pause --keep-open=yes --script=tests/xvfb_api.lua \
        --script=./suji --msg-level=all=no,suji=info,xvfb_api=info \
        "$tmp/t.mkv" 2>&1)
    rc=$?
    if printf '%s\n' "$out" | grep '^\[suji\]' | grep -qiE 'error|warn|traceback'; then
        printf 'xvfb-api: FAIL\n%s\n' "$out"
        status=1
    elif [ "$rc" -ne 0 ]; then
        printf 'xvfb-api: FAIL (exit code %s)\n%s\n' "$rc" "$out"
        status=1
    elif printf '%s\n' "$out" | grep -q 'xvfb-api: ok'; then
        printf '%s\n' "$out" | grep 'xvfb-api:'
    else
        printf 'xvfb-api: FAIL\n%s\n' "$out"
        status=1
    fi
fi

# Menus: a file with two audio tracks, two subtitle tracks and three chapters.
if [ -n "$tmp" ] && command -v ffmpeg >/dev/null 2>&1 && command -v mkvmerge >/dev/null 2>&1; then
    printf '1\n00:00:00,000 --> 00:00:30,000\nOne\n' >"$tmp/a.srt"
    printf '1\n00:00:00,000 --> 00:00:30,000\nTwo\n' >"$tmp/b.srt"
    printf 'CHAPTER01=00:00:00.000\nCHAPTER01NAME=One\nCHAPTER02=00:00:10.000\nCHAPTER02NAME=Two\nCHAPTER03=00:00:20.000\nCHAPTER03NAME=Three\n' \
        >"$tmp/chapters.txt"
    timeout 120 ffmpeg -v error -f lavfi -i testsrc=duration=30:size=320x240:rate=10 \
        -f lavfi -i sine=frequency=440:duration=30 -f lavfi -i sine=frequency=880:duration=30 \
        -i "$tmp/a.srt" -i "$tmp/b.srt" -map 0 -map 1 -map 2 -map 3 -map 4 \
        -c:v mpeg4 -c:a aac -c:s srt "$tmp/m0.mkv" >/dev/null 2>&1 &&
        timeout 60 mkvmerge -q -o "$tmp/m.mkv" --chapters "$tmp/chapters.txt" "$tmp/m0.mkv" >/dev/null 2>&1
fi
if [ -z "$tmp" ]; then
    echo "xvfb-menu: skipped (no xvfb-run)"
elif [ ! -s "$tmp/m.mkv" ]; then
    echo "xvfb-menu: skipped (could not make the test video: needs ffmpeg and mkvmerge)"
else
    out=$(timeout 60 xvfb-run -a mpv --no-config --vo=x11 --ao=null \
        --geometry=640x480 --pause --keep-open=yes --script=./suji \
        --script=tests/xvfb_menu.lua --msg-level=all=no,suji=info,xvfb_menu=info \
        --script-opts-append=suji-controls=$MENU_ROW \
        "$tmp/m.mkv" 2>&1)
    rc=$?
    if printf '%s\n' "$out" | grep '^\[suji\]' | grep -qiE 'error|warn|traceback'; then
        printf 'xvfb-menu: FAIL\n%s\n' "$out"
        status=1
    elif [ "$rc" -ne 0 ]; then
        printf 'xvfb-menu: FAIL (exit code %s)\n%s\n' "$rc" "$out"
        status=1
    elif printf '%s\n' "$out" | grep -q 'xvfb-menu: ok'; then
        printf '%s\n' "$out" | grep 'xvfb-menu:'
    else
        printf 'xvfb-menu: FAIL\n%s\n' "$out"
        status=1
    fi
fi

# Double clicks need real X events: xdotool.
if [ -z "$tmp" ] || [ ! -s "$tmp/m.mkv" ]; then
    echo "xvfb-dblclick: skipped (no test video)"
elif ! command -v xdotool >/dev/null 2>&1; then
    echo "xvfb-dblclick: skipped (no xdotool)"
else
    timeout 60 xvfb-run -a -s "-screen 0 1280x1024x24" sh tests/xvfb_dblclick.sh "$tmp/m.mkv" "$tmp/dbl.log" "$MENU_ROW"
    rc=$?
    # The speed set by the entry, then fullscreen from the second double
    # click only, at least a second later.
    sped=$(sed -n 's/^\[xvfb_dblclick\] speed 2\.0* at //p' "$tmp/dbl.log" | head -1)
    full=$(sed -n 's/^\[xvfb_dblclick\] fullscreen yes at //p' "$tmp/dbl.log" | head -1)
    if grep '^\[suji\]' "$tmp/dbl.log" | grep -qiE 'error|warn|traceback'; then
        printf 'xvfb-dblclick: FAIL\n%s\n' "$(cat "$tmp/dbl.log")"
        status=1
    elif [ "$rc" -ne 0 ]; then
        printf 'xvfb-dblclick: FAIL (exit code %s)\n%s\n' "$rc" "$(cat "$tmp/dbl.log")"
        status=1
    elif [ -z "$sped" ]; then
        printf 'xvfb-dblclick: FAIL (the menu entry was not chosen)\n%s\n' "$(cat "$tmp/dbl.log")"
        status=1
    elif [ -z "$full" ]; then
        printf 'xvfb-dblclick: FAIL (a later double click on the video did not reach mpv)\n%s\n' "$(cat "$tmp/dbl.log")"
        status=1
    elif ! awk -v a="$sped" -v b="$full" 'BEGIN { exit !(b - a > 1) }'; then
        printf 'xvfb-dblclick: FAIL (the double click on the menu toggled fullscreen)\n%s\n' "$(cat "$tmp/dbl.log")"
        status=1
    else
        echo "xvfb-dblclick: ok speed 2 at $sped, fullscreen only at $full"
    fi
fi

# An action button, clicked with xdotool.
if [ -z "$tmp" ] || [ ! -s "$tmp/t.mkv" ]; then
    echo "xvfb-actions: skipped (no test video)"
elif ! command -v xdotool >/dev/null 2>&1; then
    echo "xvfb-actions: skipped (no xdotool)"
else
    timeout 60 xvfb-run -a -s "-screen 0 1280x1024x24" sh tests/xvfb_actions.sh "$tmp/t.mkv" "$tmp/act.log" "$MENU_ROW"
    rc=$?
    if grep '^\[suji\]' "$tmp/act.log" | grep -qiE 'error|warn|traceback'; then
        printf 'xvfb-actions: FAIL\n%s\n' "$(cat "$tmp/act.log")"
        status=1
    elif [ "$rc" -ne 0 ]; then
        printf 'xvfb-actions: FAIL (exit code %s)\n%s\n' "$rc" "$(cat "$tmp/act.log")"
        status=1
    elif ! grep -q '^\[xvfb_actions\] shown true' "$tmp/act.log"; then
        printf 'xvfb-actions: FAIL (show-action not delivered)\n%s\n' "$(cat "$tmp/act.log")"
        status=1
    elif ! grep -q '^\[xvfb_actions\] clicked 1' "$tmp/act.log"; then
        printf 'xvfb-actions: FAIL (the click did not run the command)\n%s\n' "$(cat "$tmp/act.log")"
        status=1
    elif grep -q '^\[xvfb_actions\] clicked 2' "$tmp/act.log"; then
        printf 'xvfb-actions: FAIL (hide-action did not remove the button)\n%s\n' "$(cat "$tmp/act.log")"
        status=1
    elif ! grep -q '^\[xvfb_actions\] stayed 1' "$tmp/act.log"; then
        printf 'xvfb-actions: FAIL (the double click did not run the command)\n%s\n' "$(cat "$tmp/act.log")"
        status=1
    elif grep -q '^\[xvfb_actions\] stayed 2' "$tmp/act.log"; then
        printf 'xvfb-actions: FAIL (the double click ran the command twice)\n%s\n' "$(cat "$tmp/act.log")"
        status=1
    else
        echo "xvfb-actions: ok the click ran the command once, hide-action removed the button, a double click ran it once"
    fi
fi

exit $status
