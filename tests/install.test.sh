#!/usr/bin/env bash
# Tests for install/suji.sh (macOS and Linux installer). Run from anywhere:
#   bash tests/install.test.sh
#   SUJI_TEST_BASH=~/.local/opt/bash-3.2/bin/bash bash tests/install.test.sh
# The installer runs with the same bash as this file (or $SUJI_TEST_BASH), so
# running it with bash 3.2 checks the installer under the bash of macOS.
#
# Nothing is downloaded and no real config is touched: every run gets a fake
# HOME in a temporary folder, and a test copy of suji.sh whose release markers
# and thumbfast hash are those of fake local files, with a few functions
# replaced (the download, uname, where mpv is, the terminal). Everything else
# is the installer as shipped. Needs zip. Prints the failures and a count;
# exit code 0 when everything passes. SUJI_TEST_VERBOSE=1 prints every check.
# shellcheck shell=bash
# Single quotes around $ on purpose (code for another shell), variables set in
# subshells on purpose (each run gets its own environment), printf formats
# given by the tests, ls on folders the tests made themselves:
# shellcheck disable=SC2016,SC2030,SC2031,SC2059,SC2012,SC2010
set -u

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
under=${SUJI_TEST_BASH:-$BASH}

passed=0
failed=0
ok() { passed=$((passed + 1)); [ -z "${SUJI_TEST_VERBOSE:-}" ] || printf 'ok   %s\n' "$1"; }
fail() { failed=$((failed + 1)); printf 'FAIL %s\n' "$1"; show_out; }
check() { # check <name> <command...>
    local name="$1"
    shift
    if "$@"; then ok "$name"; else fail "$name"; fi
}
same() { cmp -s "$1" "$2"; }
has() { grep -qF -- "$2" "$1"; }
hasnt() { ! grep -qF -- "$2" "$1"; }
count_of() { grep -cF -- "$2" "$1"; }
is() { [ "$1" = "$2" ]; }

if ! command -v zip >/dev/null 2>&1; then echo "install: skipped (no zip)"; exit 0; fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/suji-sh-tests.XXXXXX")"
[ -n "${SUJI_TEST_KEEP:-}" ] || trap 'rm -rf "$tmp"' EXIT
# Without links on the way: on macOS the temporary folder is under /var, a link
# to /private/var, and a path the installer resolves must match the expected one.
tmp="$(cd "$tmp" && pwd -P)"
fake="$tmp/fake"
mkdir -p "$fake/zip/suji/core" "$tmp/tmpdir"

sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }

# --- fake downloads and the test copies -------------------------------------------

# suji.zip as tools/make-release.sh builds it: suji/ and LICENSE at its root.
printf '%s\n' '-- fake suji 9.9.9' >"$fake/zip/suji/main.lua"
printf '%s\n' '-- fake core' >"$fake/zip/suji/core/state.lua"
printf '%s\n' 'license' >"$fake/zip/LICENSE"
(cd "$fake/zip" && zip -qr "$fake/suji.zip" suji LICENSE)
printf '%s\n' '-- fake thumbfast' >"$fake/thumbfast.lua"
printf '%s\n' 'not what was published' >"$fake/bad.bin"
zip_url='https://github.com/SCEPTICG/suji/releases/download/v9.9.9/suji.zip'

# The release copy: markers filled in as make-release.sh does, the thumbfast
# hash of the fake one, and the overrides loaded just before main runs.
mkdir -p "$tmp/rel/install" "$tmp/dev/install"
rel="$tmp/rel/install/suji.sh"
sed -e "s|^    SUJI_VERSION='dev'\$|    SUJI_VERSION='9.9.9'|" \
    -e "s|^    SUJI_URL=''\$|    SUJI_URL='$zip_url'|" \
    -e "s|^    SUJI_SHA256=''\$|    SUJI_SHA256='$(sha "$fake/suji.zip")'|" \
    -e "s/^\(    THUMBFAST_SHA256='\)[0-9a-f]\{64\}'\$/\1$(sha "$fake/thumbfast.lua")'/" \
    -e '$d' "$repo/install/suji.sh" >"$rel"
printf '. "$SUJI_TEST_OVERRIDES"\n' >>"$rel"
tail -n 1 "$repo/install/suji.sh" >>"$rel"
# The repository copy: markers left as they are, next to a copy of suji/.
dev="$tmp/dev/install/suji.sh"
sed -e "s/^\(    THUMBFAST_SHA256='\)[0-9a-f]\{64\}'\$/\1$(sha "$fake/thumbfast.lua")'/" \
    -e '$d' "$repo/install/suji.sh" >"$dev"
printf '. "$SUJI_TEST_OVERRIDES"\n' >>"$dev"
tail -n 1 "$repo/install/suji.sh" >>"$dev"
cp -R "$repo/suji" "$tmp/dev/suji"

cat >"$tmp/overrides.sh" <<'EOF'
# Replaces what would reach outside the test: the download, the system, the terminal.
suji_fetch() {
    local f=''
    printf '%s\n' "$1" >>"$FAKE/downloads.log"
    case $1 in
        "$SUJI_URL") f=$FAKE/suji.zip ;;
        "$THUMBFAST_URL") f=$FAKE/thumbfast.lua ;;
    esac
    [ "$1" != "${SUJI_TEST_BAD:-}" ] || f=$FAKE/bad.bin
    [ "$1" != "${SUJI_TEST_FAIL:-}" ] || return 22
    [ -n "$f" ] && cp "$f" "$2"
}
suji_uname() { printf '%s' "${SUJI_TEST_OS:-Linux}"; }
suji_apple_languages() { [ -z "${SUJI_TEST_APPLE_LANGS:-}" ] || printf '%b\n' "$SUJI_TEST_APPLE_LANGS"; }
suji_find_mpv() { printf '%s' "${SUJI_TEST_MPV-/usr/bin/mpv}"; }
suji_flatpak_mpv() { [ -n "${SUJI_TEST_FLATPAK:-}" ]; }
suji_snap_mpv() { [ -n "${SUJI_TEST_SNAP:-}" ]; }
if [ -n "${SUJI_TEST_TTY+x}" ]; then suji_tty_path() { printf '%s' "$SUJI_TEST_TTY"; }; fi
EOF

# run <home> <args...>: runs the release copy (the dev copy with
# SUJI_TEST_COPY=dev), output in $out, exit code in $rc. Settings come from
# SUJI_TEST_* variables set (or not) by the caller.
out="$tmp/out.txt"
run() {
    local home=$1 copy=$rel
    shift
    [ "${SUJI_TEST_COPY:-}" != dev ] || copy=$dev
    : >"$fake/downloads.log"
    (
        export HOME="$home" TMPDIR="$tmp/tmpdir" FAKE="$fake" SUJI_TEST_OVERRIDES="$tmp/overrides.sh"
        if [ -n "${SUJI_TEST_NOLANG:-}" ]; then unset SUJI_LANG; else export SUJI_LANG="${SUJI_LANG-en}"; fi
        export SUJI_TEST_TTY="${SUJI_TEST_TTY-}"
        unset MPV_HOME XDG_CONFIG_HOME LC_ALL LC_MESSAGES
        "$under" "$copy" "$@" </dev/null
    ) >"$out" 2>&1
    rc=$?
    # Any shell error in any run (an unset variable under set -u, a bad
    # subscript...) is a failure, even when the checks after it pass.
    grep -E 'unbound variable|command not found|syntax error|bad (array )?subscript|integer expression expected|too many arguments' "$out" >>"$tmp/shell-errors.log"
}
answers() { printf "$1" >"$tmp/answers.txt"; SUJI_TEST_TTY="$tmp/answers.txt"; }
no_answers() { unset SUJI_TEST_TTY; }
newhome() { local h="$tmp/home-$1"; mkdir -p "$h/.config/mpv"; printf '%s' "$h"; }
show_out() { sed 's/^/     | /' "$out"; }
rec() { grep "^$2=" "$1/suji-installed.txt" | cut -d= -f2-; }
backups() { ls -d "$1"-respaldo-suji-* 2>/dev/null | wc -l | tr -d ' '; }
# Every path under $1 and the hash of each file: two equal listings, an untouched folder.
listing() {
    (cd "$1" && find . -print | LC_ALL=C sort | while IFS= read -r f; do
        if [ -f "$f" ]; then printf '%s %s\n' "$f" "$(sha "$f")"; else printf '%s\n' "$f"; fi
    done)
}
tmp_empty() { [ -z "$(ls -A "$tmp/tmpdir")" ]; }
block_first() { [ "$(head -n 1 "$1")" = '# >>> suji (managed block, do not edit) >>>' ]; }
crlf_lines() { LC_ALL=C grep -c $'\r$' "$1"; }

no_answers

# --- the installer itself ----------------------------------------------------------

check 'shellcheck: install/suji.sh is clean' sh -c 'command -v shellcheck >/dev/null 2>&1 || exit 0; shellcheck "$1"' _ "$repo/install/suji.sh"
check 'release markers: each once, on a line of its own' test \
    "$(grep -cx "    SUJI_VERSION='dev'" "$repo/install/suji.sh")$(grep -cx "    SUJI_URL=''" "$repo/install/suji.sh")$(grep -cx "    SUJI_SHA256=''" "$repo/install/suji.sh")" = 111
check 'thumbfast: the pinned commit and hash' has "$repo/install/suji.sh" \
    "    THUMBFAST_URL='https://raw.githubusercontent.com/po5/thumbfast/0f711de3138c9bd6718209d819ac54022c23ded2/thumbfast.lua'"
check 'thumbfast: the pinned hash' has "$repo/install/suji.sh" \
    "    THUMBFAST_SHA256='a3d08e71eae8b892f6cd39f9593ea219768e709312d176bca883841b156448bf'"
check 'the last line calls main, in braces' test "$(tail -n 1 "$repo/install/suji.sh")" = '{ main "$@"; }'

# --- usage ----------------------------------------------------------------------------

h=$(newhome usage)
run "$h" --help
check '--help: exit 0, the usage line' test "$rc" = 0 -a -n "$(grep -F 'Usage: suji.sh' "$out")"
run "$h" --bogus
check 'unknown option: exit 2' is "$rc" 2
run "$h" --action reinstall
check '--action with another value: exit 2' is "$rc" 2
run "$h" --target
check '--target without a folder: exit 2' is "$rc" 2
check 'usage errors change nothing' test ! -e "$h/.config/mpv/scripts" -a "$(backups "$h/.config/mpv")" = 0
SUJI_TEST_OS=FreeBSD run "$h" --yes
check 'another system: exit 2' test "$rc" = 2 -a -n "$(grep -F 'FreeBSD' "$out")"

# --- install, update, uninstall ---------------------------------------------------------

h=$(newhome basic)
cfg="$h/.config/mpv"
printf 'volume=50\n' >"$cfg/mpv.conf"
cp "$cfg/mpv.conf" "$tmp/basic-mpv.conf"
run "$h" --yes
check 'install: exit 0' is "$rc" 0
check 'install: scripts/suji from the release zip' same "$cfg/scripts/suji/main.lua" "$fake/zip/suji/main.lua"
check 'install: its sub-folders too' same "$cfg/scripts/suji/core/state.lua" "$fake/zip/suji/core/state.lua"
check 'install: no LICENSE in scripts' test ! -e "$cfg/scripts/LICENSE" -a ! -e "$cfg/scripts/suji/LICENSE"
check 'install: thumbfast' same "$cfg/scripts/thumbfast.lua" "$fake/thumbfast.lua"
check 'install: downloads the zip and thumbfast' test "$(wc -l <"$fake/downloads.log" | tr -d ' ')" = 2
check 'install: mpv.conf starts with the block' block_first "$cfg/mpv.conf"
check 'install: the block holds osc=no only' test "$(sed -n 2p "$cfg/mpv.conf")$(sed -n 3p "$cfg/mpv.conf")" = 'osc=no# <<< suji (managed block, do not edit) <<<'
check 'install: the rest of mpv.conf as it was' test "$(tail -n +4 "$cfg/mpv.conf")" = 'volume=50'
check 'install: thumbfast.conf created' has "$cfg/script-opts/thumbfast.conf" 'network=yes'
for o in hwdec=yes spawn_first=no max_height=200 max_width=200; do
    check "install: thumbfast.conf has $o" grep -qx "$o" "$cfg/script-opts/thumbfast.conf"
done
check 'install: no mpv_path on Linux' hasnt "$cfg/script-opts/thumbfast.conf" mpv_path
check 'install: record version' is "$(rec "$cfg" suji_version)" 9.9.9
check 'install: record says mpv.conf was there' is "$(rec "$cfg" mpv_conf_preexisting)" yes
check 'install: record says thumbfast was not' is "$(rec "$cfg" thumbfast_preexisting)" no
check 'install: record says thumbfast.conf was not' is "$(rec "$cfg" thumbfast_conf_preexisting)" no
check 'install: one backup' is "$(backups "$cfg")" 1
b=$(ls -d "$cfg"-respaldo-suji-*)
check 'install: the backup has mpv.conf as it was' same "$b/mpv.conf" "$tmp/basic-mpv.conf"
check 'install: the backup has nothing else' test "$(ls -A "$b")" = mpv.conf
check 'install: the backup name has the date' test -n "$(printf '%s' "${b##*/}" | grep -E '^mpv-respaldo-suji-[0-9]{8}-[0-9]{6}$')"
check 'install: the last line says to restart' test "$(tail -n 1 "$out")" = 'Restart the player to see the changes.'
check 'install: temporary folder removed' tmp_empty

printf '%s\n' '-- left by an old version' >"$cfg/scripts/suji/old.lua"
printf '%s\n' '# my thumbfast settings' >"$cfg/script-opts/thumbfast.conf"
run "$h" --yes
check 'update: exit 0' is "$rc" 0
check 'update: one block' is "$(count_of "$cfg/mpv.conf" '# >>> suji')" 1
check 'update: the old suji folder replaced' test ! -e "$cfg/scripts/suji/old.lua" -a -f "$cfg/scripts/suji/main.lua"
check 'update: thumbfast already as pinned is not downloaded again' test "$(cat "$fake/downloads.log")" = "$zip_url"
check 'update: thumbfast.conf of the user kept' test "$(cat "$cfg/script-opts/thumbfast.conf")" = '# my thumbfast settings'
check 'update: the record keeps what the first install saw' is "$(rec "$cfg" thumbfast_preexisting)" no
check 'update: two backups' is "$(backups "$cfg")" 2
check 'update: no temporary folder left in scripts' test -z "$(ls -A "$cfg/scripts" | grep -v -e '^suji$' -e '^thumbfast.lua$')"

printf 'scale=1.5\n' >"$cfg/script-opts/suji.conf"
printf '125\n' >"$cfg/suji-size"
run "$h" --yes --action uninstall
check 'uninstall: exit 0' is "$rc" 0
check 'uninstall: scripts/suji gone' test ! -e "$cfg/scripts/suji"
check 'uninstall: mpv.conf as before suji' same "$cfg/mpv.conf" "$tmp/basic-mpv.conf"
check 'uninstall: thumbfast removed (suji brought it)' test ! -e "$cfg/scripts/thumbfast.lua"
check 'uninstall: thumbfast.conf removed with it (suji made it)' test ! -e "$cfg/script-opts/thumbfast.conf"
check 'uninstall: suji.conf and suji-size kept by default' test -f "$cfg/script-opts/suji.conf" -a -f "$cfg/suji-size"
check 'uninstall: record removed' test ! -e "$cfg/suji-installed.txt"
check 'uninstall: empty scripts folder removed' test ! -e "$cfg/scripts"
check 'uninstall: a backup too' is "$(backups "$cfg")" 3
b=$(ls -d "$cfg"-respaldo-suji-* | LC_ALL=C sort | tail -n 1)
check 'uninstall: its backup has scripts/suji and the record' test -f "$b/scripts/suji/main.lua" -a -f "$b/suji-installed.txt"
check 'uninstall: the last line says to restart' test "$(tail -n 1 "$out")" = 'Restart the player to see the changes.'

# Uninstall answering yes to everything, through the terminal.
run "$h" --yes
answers '2\n1\ny\ny\n'
run "$h"
check 'uninstall (menu): exit 0' is "$rc" 0
check 'uninstall (menu): suji.conf and suji-size deleted on yes' test ! -e "$cfg/script-opts/suji.conf" -a ! -e "$cfg/suji-size"
check 'uninstall (menu): the folder lists suji' has "$out" 'Folders with suji:'
no_answers

# thumbfast that was there before suji stays by default.
h=$(newhome thumb)
cfg="$h/.config/mpv"
mkdir -p "$cfg/scripts" "$cfg/script-opts"
printf '%s\n' '-- my own thumbfast' >"$cfg/scripts/thumbfast.lua"
printf '%s\n' 'network=no' >"$cfg/script-opts/thumbfast.conf"
run "$h" --yes
check 'thumbfast of the user: replaced by the pinned one' same "$cfg/scripts/thumbfast.lua" "$fake/thumbfast.lua"
check 'thumbfast of the user: the backup keeps it' test -f "$(ls -d "$cfg"-respaldo-suji-*)/scripts/thumbfast.lua"
check 'thumbfast of the user: thumbfast.conf untouched on Linux' test "$(cat "$cfg/script-opts/thumbfast.conf")" = 'network=no'
run "$h" --yes --action uninstall
check 'thumbfast of the user: kept on uninstall' test -f "$cfg/scripts/thumbfast.lua" -a -f "$cfg/script-opts/thumbfast.conf"

# --- backups: three kept -------------------------------------------------------------------

h=$(newhome backups)
cfg="$h/.config/mpv"
printf 'volume=50\n' >"$cfg/mpv.conf"
mkdir -p "$cfg-respaldo-suji-20200101-000000" "$cfg-respaldo-suji-notes" "$h/.config/other-respaldo-suji-20200101-000000"
for _ in 1 2 3 4 5; do run "$h" --yes; done
check 'backups: the newest three are kept' is "$(ls -d "$cfg"-respaldo-suji-[0-9]* | wc -l | tr -d ' ')" 3
check 'backups: the oldest one is gone' test ! -e "$cfg-respaldo-suji-20200101-000000"
check 'backups: a folder not named like one stays' test -d "$cfg-respaldo-suji-notes"
check 'backups: those of another folder stay' test -d "$h/.config/other-respaldo-suji-20200101-000000"
check 'backups: the one just made is kept' has "$out" "Backup: $(ls -d "$cfg"-respaldo-suji-[0-9]* | LC_ALL=C sort -t- -k5,5n | tail -n 1)"

# --- interfaces set aside -----------------------------------------------------------------------

h=$(newhome aside)
cfg="$h/.config/mpv"
mkdir -p "$cfg/scripts/uosc" "$cfg/script-opts" "$cfg/fonts"
printf '%s\n' '-- uosc' >"$cfg/scripts/uosc/main.lua"
printf '%s\n' '-- modernz' >"$cfg/scripts/ModernZ.lua"
printf '%s\n' '-- osc' >"$cfg/scripts/osc.lua"
printf '%s\n' '-- other' >"$cfg/scripts/other.lua"
printf '%s\n' 'x=1' >"$cfg/script-opts/uosc.conf"
printf '%s\n' 'y=1' >"$cfg/script-opts/modernz.conf"
printf '%s\n' 'z=1' >"$cfg/script-opts/other.conf"
printf 'font\n' >"$cfg/fonts/modernz-icons.ttf"
printf 'font\n' >"$cfg/fonts/other.ttf"
listing "$cfg" >"$tmp/aside-before.txt"
run "$h" --yes
check 'aside: exit 0' is "$rc" 0
d="$cfg/scripts-apartados-suji"
check 'aside: uosc folder set aside' test -f "$d/uosc/main.lua" -a ! -e "$cfg/scripts/uosc"
check 'aside: ModernZ.lua set aside (any case)' test -f "$d/ModernZ.lua" -a ! -e "$cfg/scripts/ModernZ.lua"
check 'aside: osc.lua set aside' test -f "$d/osc.lua"
check 'aside: their options' test -f "$d/script-opts/uosc.conf" -a -f "$d/script-opts/modernz.conf"
check 'aside: the ModernZ font' test -f "$d/fonts/modernz-icons.ttf"
check 'aside: other scripts, options and fonts stay' test -f "$cfg/scripts/other.lua" -a -f "$cfg/script-opts/other.conf" -a -f "$cfg/fonts/other.ttf"
check 'aside: recorded' test "$(grep -c '^disabled=' "$cfg/suji-installed.txt")" = 6
check 'aside: record format' grep -qx 'disabled=scripts-apartados-suji/uosc|scripts/uosc' "$cfg/suji-installed.txt"
check 'aside: record format for options' grep -qx 'disabled=scripts-apartados-suji/script-opts/modernz.conf|script-opts/modernz.conf' "$cfg/suji-installed.txt"
b=$(ls -d "$cfg"-respaldo-suji-*)
check 'aside: the backup has what was set aside' test -f "$b/scripts/uosc/main.lua" -a -f "$b/scripts/ModernZ.lua" -a -f "$b/fonts/modernz-icons.ttf"
check 'aside: the backup has nothing it did not touch' test ! -e "$b/scripts/other.lua" -a ! -e "$b/fonts/other.ttf"
run "$h" --yes
check 'aside, update: the record keeps them' test "$(grep -c '^disabled=' "$cfg/suji-installed.txt")" = 6
run "$h" --yes --action uninstall
check 'aside, uninstall: exit 0' is "$rc" 0
check 'aside, uninstall: everything back' test -f "$cfg/scripts/uosc/main.lua" -a -f "$cfg/scripts/ModernZ.lua" -a -f "$cfg/fonts/modernz-icons.ttf" -a -f "$cfg/script-opts/uosc.conf"
check 'aside, uninstall: the set-aside folder gone' test ! -e "$d"
listing "$cfg" >"$tmp/aside-after.txt"
check 'aside, uninstall: the folder as it was before suji' same "$tmp/aside-before.txt" "$tmp/aside-after.txt"

# Kept in place when the answer is no; never overwritten when moving back.
h=$(newhome aside2)
cfg="$h/.config/mpv"
mkdir -p "$cfg/scripts"
printf '%s\n' '-- modernx' >"$cfg/scripts/modernx.lua"
answers '1\n1\nn\n'
run "$h"
check 'aside, no: left in place' test -f "$cfg/scripts/modernx.lua" -a ! -e "$cfg/scripts-apartados-suji"
check 'aside, no: said so' has "$out" 'Left in place'
no_answers
run "$h" --yes
printf '%s\n' '-- a new modernx' >"$cfg/scripts/modernx.lua"
run "$h" --yes --action uninstall
check 'aside, restore over a file: not overwritten' test "$(cat "$cfg/scripts/modernx.lua")" = '-- a new modernx'
check 'aside, restore over a file: said so' has "$out" 'not moved back'
check 'aside, restore over a file: the set-aside copy stays' test -f "$cfg/scripts-apartados-suji/modernx.lua"
# A record edited to point outside the folder is not followed.
h=$(newhome aside3)
cfg="$h/.config/mpv"
run "$h" --yes
printf '%s\n' 'secret' >"$h/outside.txt"
printf 'volume=50\n' >"$cfg/mpv.conf.mine"
printf 'disabled=../../outside.txt|scripts/x.lua\ndisabled=scripts-apartados-suji/a|/etc/passwd\n' >>"$cfg/suji-installed.txt"
printf 'disabled=mpv.conf.mine|scripts/y.lua\ndisabled=scripts-apartados-suji/b|mpv.conf.b\n' >>"$cfg/suji-installed.txt"
run "$h" --yes --action uninstall
check 'record: paths outside the folder ignored' test -f "$h/outside.txt" -a ! -e "$cfg/scripts/x.lua"
check 'record: only set-aside items moved, only back to scripts, script-opts or fonts' \
    test -f "$cfg/mpv.conf.mine" -a ! -e "$cfg/scripts/y.lua"
check 'record: said so' has "$out" 'Ignored an invalid entry'

# --- mpv.conf ------------------------------------------------------------------------------------

h=$(newhome conf-new)
cfg="$h/.config/mpv"
run "$h" --yes
check 'mpv.conf missing: created with the block only' test "$(cat "$cfg/mpv.conf")" = "$(printf '%s\n' '# >>> suji (managed block, do not edit) >>>' osc=no '# <<< suji (managed block, do not edit) <<<')"
check 'mpv.conf missing: recorded' is "$(rec "$cfg" mpv_conf_preexisting)" no
run "$h" --yes --action uninstall
check 'mpv.conf missing: deleted on uninstall' test ! -e "$cfg/mpv.conf"

h=$(newhome conf-profile)
cfg="$h/.config/mpv"
printf 'volume=50\n[anime]\nprofile-cond=1\n' >"$cfg/mpv.conf"
cp "$cfg/mpv.conf" "$tmp/profile.conf"
run "$h" --yes
check 'mpv.conf ending in a profile: the block goes first' block_first "$cfg/mpv.conf"
check 'mpv.conf ending in a profile: no [default] added' hasnt "$cfg/mpv.conf" '[default]'
run "$h" --yes --action uninstall
check 'mpv.conf ending in a profile: back as it was' same "$cfg/mpv.conf" "$tmp/profile.conf"

h=$(newhome conf-crlf)
cfg="$h/.config/mpv"
printf 'volume=50\r\nmute=yes\r\n' >"$cfg/mpv.conf"
cp "$cfg/mpv.conf" "$tmp/crlf.conf"
run "$h" --yes
check 'mpv.conf CRLF: every line still CRLF' test "$(crlf_lines "$cfg/mpv.conf")" = 5 -a "$(wc -l <"$cfg/mpv.conf" | tr -d ' ')" = 5
run "$h" --yes --action uninstall
check 'mpv.conf CRLF: back as it was' same "$cfg/mpv.conf" "$tmp/crlf.conf"

h=$(newhome conf-noeol)
cfg="$h/.config/mpv"
printf '\357\273\277volume=50' >"$cfg/mpv.conf"
cp "$cfg/mpv.conf" "$tmp/noeol.conf"
run "$h" --yes
check 'mpv.conf with a BOM: the BOM stays first' test "$(head -c 3 "$cfg/mpv.conf" | od -An -tx1 | tr -d ' \n')" = efbbbf
check 'mpv.conf with a BOM: the block still found' test "$(count_of "$cfg/mpv.conf" '# >>> suji')" = 1
run "$h" --yes
check 'mpv.conf with a BOM: one block after an update' test "$(count_of "$cfg/mpv.conf" '# >>> suji')" = 1
run "$h" --yes --action uninstall
check 'mpv.conf with a BOM and no final line break: back as it was' same "$cfg/mpv.conf" "$tmp/noeol.conf"

h=$(newhome conf-moved)
cfg="$h/.config/mpv"
run "$h" --yes
printf 'volume=50\n' >"$cfg/mpv.conf.new"
cat "$cfg/mpv.conf" >>"$cfg/mpv.conf.new"
mv "$cfg/mpv.conf.new" "$cfg/mpv.conf"
run "$h" --yes
check 'mpv.conf, block moved by the user: updated where it is' test "$(head -n 1 "$cfg/mpv.conf")" = volume=50 -a "$(count_of "$cfg/mpv.conf" '# >>> suji')" = 1

for broken in begin end twice; do
    h=$(newhome "conf-$broken")
    cfg="$h/.config/mpv"
    case $broken in
        begin) printf 'volume=50\n# >>> suji (managed block, do not edit) >>>\nosc=no\n' >"$cfg/mpv.conf" ;;
        end) printf 'osc=no\n# <<< suji (managed block, do not edit) <<<\n' >"$cfg/mpv.conf" ;;
        twice)
            printf '%s\n' '# >>> suji (managed block, do not edit) >>>' osc=no '# <<< suji (managed block, do not edit) <<<' \
                '# >>> suji (managed block, do not edit) >>>' osc=no '# <<< suji (managed block, do not edit) <<<' >"$cfg/mpv.conf"
            ;;
    esac
    mkdir -p "$cfg/scripts"
    printf '%s\n' '-- osc' >"$cfg/scripts/osc.lua"
    listing "$cfg" >"$tmp/broken-before.txt"
    run "$h" --yes
    check "mpv.conf with a broken block ($broken): exit 1" is "$rc" 1
    check "mpv.conf with a broken block ($broken): said so" has "$out" 'incomplete or repeated suji block'
    listing "$cfg" >"$tmp/broken-after.txt"
    check "mpv.conf with a broken block ($broken): nothing changed" same "$tmp/broken-before.txt" "$tmp/broken-after.txt"
    check "mpv.conf with a broken block ($broken): no backup" is "$(backups "$cfg")" 0
    run "$h" --yes --action uninstall --target "$cfg"
    check "mpv.conf with a broken block ($broken): uninstall stops too" test "$rc" = 1 -a "$(backups "$cfg")" = 0
done

# --- thumbfast.conf and mpv_path on macOS -----------------------------------------------------------

h=$(newhome mac)
cfg="$h/.config/mpv"
SUJI_TEST_OS=Darwin SUJI_TEST_MPV=/opt/homebrew/bin/mpv run "$h" --yes
check 'macOS: exit 0' is "$rc" 0
check 'macOS: new thumbfast.conf has mpv_path' grep -qx 'mpv_path=/opt/homebrew/bin/mpv' "$cfg/script-opts/thumbfast.conf"
check 'macOS: and the usual settings' grep -qx 'max_width=200' "$cfg/script-opts/thumbfast.conf"
SUJI_TEST_OS=Darwin SUJI_TEST_MPV=/opt/homebrew/bin/mpv run "$h" --yes
check 'macOS: mpv_path not added twice' test "$(grep -c mpv_path= "$cfg/script-opts/thumbfast.conf")" = 1

h=$(newhome mac-conf)
cfg="$h/.config/mpv"
mkdir -p "$cfg/script-opts"
printf 'network=no\r\nmax_width=300' >"$cfg/script-opts/thumbfast.conf"
SUJI_TEST_OS=Darwin SUJI_TEST_MPV=/Applications/mpv.app/Contents/MacOS/mpv run "$h" --yes
check 'macOS, thumbfast.conf of the user: kept' test "$(head -n 2 "$cfg/script-opts/thumbfast.conf" | tr -d '\r')" = "$(printf 'network=no\nmax_width=300')"
check 'macOS, thumbfast.conf of the user: mpv_path of mpv.app added' grep -q '^mpv_path=/Applications/mpv.app/Contents/MacOS/mpv' "$cfg/script-opts/thumbfast.conf"
check 'macOS, thumbfast.conf of the user: CRLF kept' test "$(crlf_lines "$cfg/script-opts/thumbfast.conf")" = "$(wc -l <"$cfg/script-opts/thumbfast.conf" | tr -d ' ')"
check 'macOS, thumbfast.conf of the user: in the backup' test -f "$(ls -d "$cfg"-respaldo-suji-*)/script-opts/thumbfast.conf"

h=$(newhome mac-path)
cfg="$h/.config/mpv"
mkdir -p "$cfg/script-opts"
printf 'mpv_path=/somewhere/mpv\n' >"$cfg/script-opts/thumbfast.conf"
SUJI_TEST_OS=Darwin SUJI_TEST_MPV=/opt/homebrew/bin/mpv run "$h" --yes
check 'macOS, thumbfast.conf with mpv_path: untouched' test "$(cat "$cfg/script-opts/thumbfast.conf")" = 'mpv_path=/somewhere/mpv'

# --- hikari ---------------------------------------------------------------------------------------

h=$(newhome hikari)
cfg="$h/.config/mpv"
mkdir -p "$cfg/scripts/uosc"
printf '%s\n' '-- hikari' >"$cfg/scripts/hikari-palettes.lua"
printf '%s\n' '-- uosc' >"$cfg/scripts/uosc/main.lua"
printf 'osc=no\n' >"$cfg/mpv.conf"
listing "$cfg" >"$tmp/hikari-before.txt"
run "$h" --yes
check 'hikari: exit 2 (nothing to do)' is "$rc" 2
check 'hikari: points to its installer' has "$out" '-Interface suji'
listing "$cfg" >"$tmp/hikari-after.txt"
check 'hikari: the folder untouched' same "$tmp/hikari-before.txt" "$tmp/hikari-after.txt"
check 'hikari: no backup' is "$(backups "$cfg")" 0
check 'hikari: nothing downloaded' test ! -s "$fake/downloads.log"
run "$h" --yes --action uninstall --target "$cfg"
check 'hikari: uninstall refused too' test "$rc" = 2 -a "$(backups "$cfg")" = 0
rm "$cfg/scripts/hikari-palettes.lua"
printf 'hikari_version=0.6.0\n' >"$cfg/hikari-installed.txt"
run "$h" --yes
check 'hikari (record only): refused' test "$rc" = 2 -a ! -e "$cfg/scripts/suji"
# In a menu, the folder is listed with a tag and refused when chosen.
answers '1\n1\n'
run "$h"
check 'hikari, menu: tagged' has "$out" '[hikari: use its installer]'
check 'hikari, menu: refused, exit 0' test "$rc" = 0 -a ! -e "$cfg/scripts/suji"
no_answers

# --- a download that does not match ------------------------------------------------------------------

for what in zip thumbfast; do
    h=$(newhome "bad-$what")
    cfg="$h/.config/mpv"
    mkdir -p "$cfg/scripts"
    printf 'volume=50\n' >"$cfg/mpv.conf"
    printf '%s\n' '-- osc' >"$cfg/scripts/osc.lua"
    listing "$cfg" >"$tmp/bad-before.txt"
    if [ "$what" = zip ]; then bad=$zip_url; else bad=$(sed -n "s/^    THUMBFAST_URL='\(.*\)'\$/\1/p" "$rel"); fi
    SUJI_TEST_BAD=$bad run "$h" --yes
    check "hash mismatch ($what): exit 1" is "$rc" 1
    check "hash mismatch ($what): said so" has "$out" 'does not match its expected SHA256'
    listing "$cfg" >"$tmp/bad-after.txt"
    check "hash mismatch ($what): the folder untouched" same "$tmp/bad-before.txt" "$tmp/bad-after.txt"
    check "hash mismatch ($what): no backup" is "$(backups "$cfg")" 0
    check "hash mismatch ($what): temporary folder removed" tmp_empty
done
h=$(newhome fail)
SUJI_TEST_FAIL=$zip_url run "$h" --yes
check 'failed download: exit 1, nothing installed' test "$rc" = 1 -a ! -e "$h/.config/mpv/scripts"
check 'failed download: said so' has "$out" 'Could not download'

# --- choosing folders -------------------------------------------------------------------------------

h=$(newhome many)
mkdir -p "$h/.var/app/io.mpv.Mpv/config/mpv"
SUJI_TEST_FLATPAK=1 run "$h" --yes
check 'several folders without questions: exit 2' is "$rc" 2
check 'several folders without questions: lists them' has "$out" 'mpv (Flatpak)'
answers '1\n1,2\n'
SUJI_TEST_FLATPAK=1 run "$h"
check 'several folders, both chosen: exit 0' is "$rc" 0
check 'several folders, both chosen: both installed' test -f "$h/.config/mpv/scripts/suji/main.lua" -a -f "$h/.var/app/io.mpv.Mpv/config/mpv/scripts/suji/main.lua"
check 'several folders, both chosen: the summary' has "$out" 'Done: 2 of 2 folders.'
check 'several folders: downloaded once' test "$(wc -l <"$fake/downloads.log" | tr -d ' ')" = 2
check 'Flatpak: no mpv_path' test ! -e "$h/.var/app/io.mpv.Mpv/config/mpv/script-opts/thumbfast.conf" -o -z "$(grep mpv_path "$h/.var/app/io.mpv.Mpv/config/mpv/script-opts/thumbfast.conf")"
answers '0\n'
run "$h"
check 'menu: exit chosen, exit 0' test "$rc" = 0 -a -n "$(grep -F 'Cancelled.' "$out")"
mkdir -p "$h/other"
answers "1\no\n$h/other/mpv\n"
run "$h"
check 'another folder typed: installed there' test "$rc" = 0 -a -f "$h/other/mpv/scripts/suji/main.lua"
no_answers

h=$(newhome target)
mkdir -p "$h/notmpv"
printf 'x\n' >"$h/notmpv/file.txt"
run "$h" --yes --target "$h/notmpv"
check 'a folder that is not mpv'"'"'s, without questions: exit 2' test "$rc" = 2 -a ! -e "$h/notmpv/scripts"
run "$h" --yes --target "$h"
check 'the home folder: refused' test "$rc" = 2 -a ! -e "$h/scripts"
run "$h" --yes --target "$h/custom/mpv"
check '--target: a new folder' test "$rc" = 0 -a -f "$h/custom/mpv/scripts/suji/main.lua"
check '--target: no backup for a new folder' is "$(backups "$h/custom/mpv")" 0
SUJI_TEST_MPV='' run "$h" --yes --target "$h/custom/mpv"
check 'no mpv: only a warning' test "$rc" = 0 -a -n "$(grep -F 'mpv was not found' "$out")"

h=$(newhome nothing)
run "$h" --yes --action uninstall
check 'uninstall with nothing installed: exit 2' test "$rc" = 2 -a -n "$(grep -F 'does not seem to be installed' "$out")"

# --- the repository copy, and the language ---------------------------------------------------------

h=$(newhome dev)
SUJI_TEST_COPY=dev run "$h" --yes
check 'repository copy: installs its suji folder' diff -r "$repo/suji" "$h/.config/mpv/scripts/suji"
check 'repository copy: records dev' is "$(rec "$h/.config/mpv" suji_version)" dev
check 'repository copy: downloads thumbfast only' test "$(wc -l <"$fake/downloads.log" | tr -d ' ')" = 1

h=$(newhome es)
SUJI_LANG=es run "$h" --yes
check 'Spanish: the messages' has "$out" 'Reinicia el reproductor para ver los cambios.'
h=$(newhome lang)
SUJI_TEST_NOLANG=1 LANG=es_ES.UTF-8 run "$h" --help
check 'LANG=es_ES: Spanish' has "$out" 'Uso: suji.sh'
SUJI_TEST_NOLANG=1 LANG=en_US.UTF-8 run "$h" --help
check 'LANG=en_US: English' has "$out" 'Usage: suji.sh'
SUJI_TEST_NOLANG=1 LANG=en_US.UTF-8 SUJI_TEST_OS=Darwin SUJI_TEST_APPLE_LANGS='(\n    "es-ES",\n    "en-US"\n)' run "$h" --help
check 'macOS set to Spanish: Spanish' has "$out" 'Uso: suji.sh'

check 'no shell errors in any run' test ! -s "$tmp/shell-errors.log"
[ ! -s "$tmp/shell-errors.log" ] || sed 's/^/     | /' "$tmp/shell-errors.log"

printf 'install.test.sh: %s passed, %s failed (bash %s)\n' "$passed" "$failed" "$("$under" -c 'echo "$BASH_VERSION"')"
[ "$failed" = 0 ]
