#!/usr/bin/env bash
# Builds the files of a suji release in dist/. It uploads nothing.
#
#   tools/make-release.sh vX.Y.Z
#
#   dist/suji.zip     suji/ and LICENSE of the current commit (git archive: the
#                     committed files, nothing from the work tree)
#   dist/suji.ps1     install/suji.ps1 of the current commit with its three release
#                     markers filled in: the version, the URL of this release's
#                     suji.zip and that zip's SHA256
#   dist/suji.sh      install/suji.sh (macOS and Linux) of the current commit,
#                     with the same three markers filled in
#   dist/SHA256SUMS   SHA256 of the three files
#
# The tag vX.Y.Z must already exist and point to the current commit. Then push
# the tag, create the GitHub release of SCEPTICG/suji from it, attach
# dist/suji.ps1, dist/suji.sh, dist/suji.zip and dist/SHA256SUMS with those
# names and publish it as Latest. dist/suji.ps1 and dist/suji.sh only install
# the suji.zip published under that same tag, and only if its SHA256 matches.
#
# Needs: git, a SHA256 tool (sha256sum or shasum), awk, bash, and PowerShell 7
# (pwsh in PATH, $PWSH, or ~/.local/opt/powershell/pwsh) to check that
# suji.ps1 still parses.
set -euo pipefail

die() { printf 'make-release: %s\n' "$*" >&2; exit 1; }

readonly RELEASE_BASE='https://github.com/SCEPTICG/suji/releases/download'

tag="${1:-}"
[[ $# -eq 1 ]] || die "usage: tools/make-release.sh vX.Y.Z"
[[ "$tag" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] ||
    die "the tag must look like vX.Y.Z (e.g. v0.6.0), not '$tag'"
version="${tag#v}"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
[[ "$(git rev-parse --show-toplevel)" == "$root" ]] || die "$root is not the top of a git repository"

[[ -z "$(git status --porcelain --untracked-files=normal)" ]] ||
    die "the work tree is not clean (commit or remove the changes first): the release must be exactly a commit"
commit="$(git rev-parse --verify HEAD)"
# The release must be built from the very commit its tag names: the GitHub
# release is created from that tag, and the installers point at its suji.zip.
git rev-parse -q --verify "refs/tags/$tag" >/dev/null ||
    die "tag $tag does not exist: create it on this commit first (git tag $tag), build, then push it (git push origin $tag)"
# By its full name: a branch called like the tag must not be taken instead.
tagged="$(git rev-parse "refs/tags/$tag^{commit}")"
[[ "$tagged" == "$commit" ]] || die "tag $tag points to $tagged, not to HEAD ($commit): move it first"

if command -v sha256sum >/dev/null 2>&1; then
    sha256() { sha256sum "$1" | cut -d' ' -f1; }
elif command -v shasum >/dev/null 2>&1; then
    sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }
else
    die "no sha256sum or shasum found"
fi

pwsh_bin="${PWSH:-}"
if [[ -z "$pwsh_bin" ]]; then
    if command -v pwsh >/dev/null 2>&1; then pwsh_bin="$(command -v pwsh)"
    elif [[ -x "$HOME/.local/opt/powershell/pwsh" ]]; then pwsh_bin="$HOME/.local/opt/powershell/pwsh"
    else die "PowerShell 7 (pwsh) not found: set PWSH to its path"
    fi
fi

for f in suji/main.lua LICENSE install/suji.ps1 install/suji.sh; do
    git cat-file -e "HEAD:$f" 2>/dev/null || die "$f is not in the commit"
done

mkdir -p dist
cleanup() { rm -f dist/suji.zip dist/suji.ps1.tmp dist/suji.sh.tmp; }
rm -f dist/suji.zip dist/suji.ps1 dist/suji.sh dist/SHA256SUMS dist/suji.ps1.tmp dist/suji.sh.tmp

git archive --format=zip -o dist/suji.zip HEAD -- suji LICENSE
zip_sha="$(sha256 dist/suji.zip)"
[[ "$zip_sha" =~ ^[0-9a-f]{64}$ ]] || { cleanup; die "could not hash dist/suji.zip"; }
url="$RELEASE_BASE/$tag/suji.zip"

# fill <file in the commit> <out> <marker 1> <line 1> <marker 2> <line 2> <marker 3> <line 3>:
# each marker a whole line, exactly once. The values are a checked version, a
# URL built from the checked tag and a hex hash: nothing in them can break out
# of the quotes.
fill() {
    git show "HEAD:$1" | awk -v m1="$3" -v r1="$4" -v m2="$5" -v r2="$6" -v m3="$7" -v r3="$8" '
        $0 == m1 { print r1; c1++; next }
        $0 == m2 { print r2; c2++; next }
        $0 == m3 { print r3; c3++; next }
        { print }
        END {
            if (c1 != 1 || c2 != 1 || c3 != 1) {
                printf "make-release: release markers found %d, %d and %d times (each must be there exactly once)\n", c1, c2, c3 > "/dev/stderr"
                exit 1
            }
        }' >"$2" || { cleanup; die "could not fill in the release markers of $1"; }
    local changed
    changed="$(git show "HEAD:$1" | diff - "$2" | grep -c '^>' || true)"
    [[ "$changed" == 3 ]] || { cleanup; die "expected 3 changed lines in $1, got $changed"; }
}

fill install/suji.ps1 dist/suji.ps1.tmp \
    "\$script:SujiVersion = 'dev'" "\$script:SujiVersion = '$version'" \
    "\$script:SujiUrl = ''" "\$script:SujiUrl = '$url'" \
    "\$script:SujiSha256 = ''" "\$script:SujiSha256 = '$zip_sha'"

# Windows PowerShell 5.1 reads a BOM-less script as ANSI: it must stay ASCII.
non_ascii="$(LC_ALL=C tr -d '\000-\177' <dist/suji.ps1.tmp | wc -c | tr -d ' ')"
[[ "$non_ascii" == 0 ]] || { cleanup; die "dist/suji.ps1 has $non_ascii non-ASCII bytes"; }

# shellcheck disable=SC2016 # PowerShell code, expanded by pwsh.
SUJI_PARSE_FILE="$root/dist/suji.ps1.tmp" "$pwsh_bin" -NoProfile -NonInteractive -Command '
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($env:SUJI_PARSE_FILE, [ref]$null, [ref]$errors)
    if (@($errors).Count -gt 0) { foreach ($e in $errors) { [Console]::Error.WriteLine($e.ToString()) }; exit 1 }
    exit 0' || { cleanup; die "dist/suji.ps1 does not parse"; }

# The same three markers in install/suji.sh (indented, inside suji_defaults).
fill install/suji.sh dist/suji.sh.tmp \
    "    SUJI_VERSION='dev'" "    SUJI_VERSION='$version'" \
    "    SUJI_URL=''" "    SUJI_URL='$url'" \
    "    SUJI_SHA256=''" "    SUJI_SHA256='$zip_sha'"
# The last line must still be the call to main, in braces: a download cut short
# (even inside that line) runs nothing.
# shellcheck disable=SC2016 # the line itself, not an expansion.
[[ "$(tail -n 1 dist/suji.sh.tmp)" == '{ main "$@"; }' ]] || { cleanup; die "dist/suji.sh does not end with the call to main"; }
bash -n dist/suji.sh.tmp || { cleanup; die "dist/suji.sh does not parse"; }

mv dist/suji.ps1.tmp dist/suji.ps1
mv dist/suji.sh.tmp dist/suji.sh
ps1_sha="$(sha256 dist/suji.ps1)"
sh_sha="$(sha256 dist/suji.sh)"
printf '%s  suji.ps1\n%s  suji.sh\n%s  suji.zip\n' "$ps1_sha" "$sh_sha" "$zip_sha" >dist/SHA256SUMS

cat <<EOF
suji $version ($tag) built from commit $commit:
  dist/suji.ps1  $ps1_sha
  dist/suji.sh   $sh_sha
  dist/suji.zip  $zip_sha
  dist/SHA256SUMS
suji.ps1 and suji.sh install from $url
Nothing was uploaded. Next: git push origin $tag, create the GitHub release
from that tag, attach the four files with these names, publish it as Latest.
EOF
