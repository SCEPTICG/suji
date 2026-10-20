#!/bin/sh
# Runs the unit tests with Lua 5.1 (or $LUA), a smoke test with a windowless
# mpv and, if xvfb-run is installed, a real drag test in a virtual display.
# Usage: tests/run.sh   (from anywhere; needs lua5.1, mpv is optional)
set -u
cd "$(dirname "$0")/.." || exit 1
LUA=${LUA:-lua5.1}
export LUA_PATH="./suji/?.lua;./tests/?.lua;;"
status=0

for t in tests/test_*.lua; do
    "$LUA" "$t" || status=1
done

if ! command -v mpv >/dev/null 2>&1; then
    echo "smoke: skipped (no mpv)"
    echo "xvfb-drag: skipped (no mpv)"
    exit $status
fi

# Only suji's own lines count: errors and warnings from suji or from Lua.
out=$(timeout 60 mpv --no-config --osc=no --vo=null --ao=null --script=./suji \
    --script-opts=suji-debug=yes --length=2 --msg-level=all=no,suji=info \
    'av://lavfi:testsrc=duration=10' 2>&1)
if printf '%s\n' "$out" | grep '^\[suji\]' | grep -qiE 'error|warn|traceback'; then
    printf 'smoke: FAIL\n%s\n' "$out"
    status=1
elif ! printf '%s\n' "$out" | grep -q '^\[suji\] start:'; then
    printf 'smoke: FAIL (suji did not start)\n%s\n' "$out"
    status=1
else
    echo "smoke: ok"
fi

if command -v xvfb-run >/dev/null 2>&1; then
    tmp=$(mktemp -d) || exit 1
    trap 'rm -rf "$tmp"' EXIT
    # A file with a fixed 60 s duration (lavfi sources grow while playing).
    timeout 120 mpv --no-config --really-quiet --o="$tmp/t.mkv" --ovc=mpeg4 \
        'av://lavfi:testsrc=duration=60:size=320x240:rate=10' >/dev/null 2>&1
    out=$(timeout 60 xvfb-run -a mpv --no-config --osc=no --vo=x11 --ao=null \
        --geometry=640x480 --pause --keep-open=yes --script=./suji \
        --script=tests/xvfb_drag.lua --msg-level=all=no,suji=warn,xvfb_drag=info \
        "$tmp/t.mkv" 2>&1)
    if printf '%s\n' "$out" | grep -q 'xvfb-drag: ok'; then
        printf '%s\n' "$out" | grep 'xvfb-drag:'
    else
        printf 'xvfb-drag: FAIL\n%s\n' "$out"
        status=1
    fi
else
    echo "xvfb-drag: skipped (no xvfb-run)"
fi

exit $status
