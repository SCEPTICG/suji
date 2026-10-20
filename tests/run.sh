#!/bin/sh
# Runs the unit tests with Lua 5.1 and a smoke test with a windowless mpv.
# Usage: tests/run.sh   (from anywhere; needs lua5.1, mpv is optional)
set -u
cd "$(dirname "$0")/.." || exit 1
LUA=${LUA:-lua5.1}
export LUA_PATH="./suji/?.lua;./tests/?.lua;;"
status=0

for t in tests/test_*.lua; do
    "$LUA" "$t" || status=1
done

if command -v mpv >/dev/null 2>&1; then
    out=$(timeout 60 mpv --no-config --vo=null --ao=null --script=./suji \
        --script-opts=suji-debug=yes --length=2 --msg-level=all=warn,suji=info \
        'av://lavfi:testsrc=duration=10' 2>&1)
    if printf '%s\n' "$out" | grep -qiE 'error|warn|traceback|stack'; then
        printf 'smoke: FAIL\n%s\n' "$out"
        status=1
    elif ! printf '%s\n' "$out" | grep -q 'suji.*start:'; then
        printf 'smoke: FAIL (suji did not start)\n%s\n' "$out"
        status=1
    else
        echo "smoke: ok"
    fi
else
    echo "smoke: skipped (no mpv)"
fi

exit $status
