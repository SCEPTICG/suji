#!/bin/sh
# Runs the unit tests with Lua 5.1 (or $LUA), a smoke test with a windowless
# mpv and, if xvfb-run is installed, a real drag and click test in a virtual
# display.
# Usage: tests/run.sh   (from anywhere; needs lua5.1, mpv is optional)
set -u
cd "$(dirname "$0")/.." || exit 1
LUA=${LUA:-lua5.1}
export LUA_PATH="./suji/?.lua;./tests/?.lua;;"
status=0
tmp=

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
if printf '%s\n' "$out" | grep '^\[suji\]' | grep -qiE 'error|warn|traceback'; then
    printf 'smoke: FAIL\n%s\n' "$out"
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
        --msg-level=all=no,suji=info,xvfb_drag=info \
        "$tmp/t.mkv" 2>&1)
    if printf '%s\n' "$out" | grep '^\[suji\]' | grep -qiE 'error|warn|traceback'; then
        printf 'xvfb-drag: FAIL\n%s\n' "$out"
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

exit $status
