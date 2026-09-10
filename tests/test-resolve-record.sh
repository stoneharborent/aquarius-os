#!/usr/bin/bash
# =============================================================================
# test-resolve-record.sh — the Resolve install record can be sourced safely
# =============================================================================
# WHAT THIS PROVES, AND THE FAULT IT COMES FROM
#
# ⚠️ THE BENCH FINDING OF 9 SEPTEMBER 2026. `aq resolve status` printed
#
#     /home/rorobeckley/.local/share/aquarius/resolve/installed.env: line 10:
#     name: command not found
#
# The installer writes a small NAME=value file when Resolve is set up, and
# `aq resolve status` reads it by sourcing it — handing it to the shell as if it
# were a script. Line 10 of that file was
#
#     AQ_RESOLVE_VERSION_FROM=the name of the file downloaded from Blackmagic
#
# with no quotes. To a shell that means "set the variable to `the`, then run a
# command called `name`". A note meant for people became a command. Nothing
# broke that day beyond the message, but the same line shape would swallow a
# file name with a space in it — which is what a browser produces the second
# time anyone downloads the same file, `DaVinci_Resolve_Studio_21_Linux (1).zip`
# — and that value IS read back and shown.
#
# The fix is that the installer now writes every value in single quotes, the way
# a shell wants them, and both readers take the quotes back off. This test
# checks the fix from both ends:
#
#   1. it writes a record through the installer's own write_record, with the
#      nastiest values it can think of — spaces, a quote, a dollar sign, a
#      backtick, a semicolon — and a plain empty value;
#   2. it sources that file the way `aq resolve status` does, under `set -eu`,
#      and requires: nothing printed on standard error, nothing run, and every
#      variable equal to exactly what went in;
#   3. it reads the same file back through the installer's own record_value and
#      through the updater's Python reader, and requires the same answers;
#   4. it hands both readers a record written the OLD way, without quotes, and
#      requires that they still read it — a machine set up before 9 September
#      keeps its record until the next update rewrites it.
#
# HOW TO RUN IT
#   ./tests/test-resolve-record.sh
#   ./tests/test-resolve-record.sh /usr/libexec/aquarius-resolve-install \
#                                  /usr/libexec/aquarius-resolve-updater
#
# It needs bash, python3 and a writable temporary folder. No Resolve, no
# container, no podman: the functions under test are lifted out of the two
# scripts by name, so the whole installer never runs.
# =============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
INSTALLER="${1:-${HERE}/../system_files/usr/libexec/aquarius-resolve-install}"
UPDATER="${2:-${HERE}/../system_files/usr/libexec/aquarius-resolve-updater}"

[ -r "${INSTALLER}" ] || { echo "not found: ${INSTALLER}" >&2; exit 2; }
[ -r "${UPDATER}" ] || { echo "not found: ${UPDATER}" >&2; exit 2; }

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

FAILED=0
pass() { echo "  ok   $*"; }
fail() { echo "  FAIL $*"; FAILED=1; }

# -----------------------------------------------------------------------------
# Lift one function out of a script, by name. A function in these scripts
# starts with `name() {` at the left margin and ends with `}` at the left
# margin; this copies everything between, comments and all, so the test runs
# the exact code that ships and not a re-typing of it.
# -----------------------------------------------------------------------------
lift() { # lift <script> <function name>
    awk -v name="$2" '
        $0 ~ "^" name "\\(\\) \\{" { p = 1 }
        p { print }
        p && /^}/ { exit }
    ' "$1"
}

for fn in record_quote record_value write_record edition_from_name version_from_name; do
    lift "${INSTALLER}" "${fn}" > "${TMP}/${fn}.sh"
    [ -s "${TMP}/${fn}.sh" ] || { echo "could not find ${fn}() in ${INSTALLER}" >&2; exit 2; }
    # shellcheck source=/dev/null
    . "${TMP}/${fn}.sh"
done

# The updater's reader is a Python function. Lift it the same way — from its
# `def` to the next line at the left margin — and run it against a file path,
# with the one GLib call it makes for the home folder stubbed out.
lift_py() { # lift_py <script> <function name>
    awk -v name="$2" '
        $0 ~ "^def " name "\\(" { p = 1; print; next }
        p && /^[^ \t]/ { exit }
        p { print }
    ' "$1"
}
lift_py "${UPDATER}" record_values > "${TMP}/record_values.py"
[ -s "${TMP}/record_values.py" ] || { echo "could not find record_values() in ${UPDATER}" >&2; exit 2; }

# read_py <file> <NAME>  → prints what the updater would see for NAME
read_py() {
    XDG_DATA_HOME="${TMP}/xdg-$$" python3 - "$1" "$2" << PY
import os, shlex, sys
class GLib:  # the updater asks GLib for the home folder; here it is never reached
    @staticmethod
    def get_home_dir(): return "/nonexistent"
$(cat "${TMP}/record_values.py")
# Point the reader at the file under test by giving it the folder layout it expects.
data_home = os.environ["XDG_DATA_HOME"]
os.makedirs(os.path.join(data_home, "aquarius", "resolve"), exist_ok=True)
with open(sys.argv[1], "rb") as src, open(os.path.join(data_home, "aquarius", "resolve", "installed.env"), "wb") as dst:
    dst.write(src.read())
sys.stdout.write(record_values().get(sys.argv[2], ""))
PY
}

# -----------------------------------------------------------------------------
# 1. Write a record with the worst values we can think of
# -----------------------------------------------------------------------------
echo "1. Writing a record through write_record"
NASTY_INSTALLER="${TMP}/DaVinci_Resolve_Studio_21.0.4_Linux (Royce's copy) \$HOME \`date\`; echo oops.zip"
NASTY_IMAGE="ghcr.io/stoneharborent/aquarius-resolve-runtime:9 with a space"
NASTY_DIGEST="ghcr.io/stoneharborent/aquarius-resolve-runtime@sha256:0123456789abcdef"
NASTY_GPU="none"
RECORD="${TMP}/installed.env"
write_record "${RECORD}" "${NASTY_INSTALLER}" "${NASTY_IMAGE}" "${NASTY_DIGEST}" "${NASTY_GPU}"

[ -s "${RECORD}" ] && pass "the file was written" || fail "the file was not written"

if grep -q '^AQ_RESOLVE_VERSION_FROM=the ' "${RECORD}"; then
    fail "AQ_RESOLVE_VERSION_FROM is still unquoted — the bench fault is back"
else
    pass "AQ_RESOLVE_VERSION_FROM is not bare words"
fi

# Every value line must be NAME='...'. Comments may say what they like.
if grep -v '^#' "${RECORD}" | grep -v "^AQ_RESOLVE_[A-Z_]*='.*'$" | grep -q .; then
    fail "a value line is not written as NAME='value':"
    grep -v '^#' "${RECORD}" | grep -v "^AQ_RESOLVE_[A-Z_]*='.*'$" | sed 's/^/         /'
else
    pass "every value line is NAME='value'"
fi

# -----------------------------------------------------------------------------
# 2. Source it the way `aq resolve status` does
# -----------------------------------------------------------------------------
echo "2. Sourcing it the way aq resolve status does"
# A fresh bash, strict like aq, that sources the file and then prints each
# variable on its own line for us to compare. Anything on standard error is a
# failure; a command called `name`, `oops` or `date` running is a failure.
SOURCE_OUT="${TMP}/source.out"
SOURCE_ERR="${TMP}/source.err"
if bash -c '
    set -euo pipefail
    . "$1"
    printf "%s\n" "${AQ_RESOLVE_SOURCE}" "${AQ_RESOLVE_IMAGE}" "${AQ_RESOLVE_DIGEST}" \
        "${AQ_RESOLVE_GPU_METHOD}" "${AQ_RESOLVE_EDITION}" "${AQ_RESOLVE_VERSION}" \
        "${AQ_RESOLVE_VERSION_FROM}"
' _ "${RECORD}" > "${SOURCE_OUT}" 2> "${SOURCE_ERR}"; then
    pass "sourcing it exits cleanly"
else
    fail "sourcing it failed (exit $?)"
fi
if [ -s "${SOURCE_ERR}" ]; then
    fail "sourcing it printed on standard error:"
    sed 's/^/         /' "${SOURCE_ERR}"
else
    pass "sourcing it printed nothing on standard error"
fi
if grep -q 'oops' "${SOURCE_OUT}" && ! grep -q 'echo oops' "${SOURCE_OUT}"; then
    fail "the semicolon in the file name ran a command"
fi

mapfile -t GOT < "${SOURCE_OUT}"
check_var() { # check_var <what> <wanted> <got>
    if [ "$2" = "$3" ]; then
        pass "$1 came back exactly"
    else
        fail "$1 changed on the way through"
        echo "         wanted: $2"
        echo "         got   : $3"
    fi
}
check_var "AQ_RESOLVE_SOURCE (spaces, a quote, \$HOME, a backtick, a semicolon)" \
    "$(basename "${NASTY_INSTALLER}")" "${GOT[0]:-}"
check_var "AQ_RESOLVE_IMAGE" "${NASTY_IMAGE}" "${GOT[1]:-}"
check_var "AQ_RESOLVE_DIGEST" "${NASTY_DIGEST}" "${GOT[2]:-}"
check_var "AQ_RESOLVE_GPU_METHOD" "${NASTY_GPU}" "${GOT[3]:-}"
check_var "AQ_RESOLVE_EDITION" "studio" "${GOT[4]:-}"
check_var "AQ_RESOLVE_VERSION" "21.0.4" "${GOT[5]:-}"
check_var "AQ_RESOLVE_VERSION_FROM" "the name of the file downloaded from Blackmagic" "${GOT[6]:-}"

# -----------------------------------------------------------------------------
# 3. The other two readers agree
# -----------------------------------------------------------------------------
echo "3. The installer's and the updater's readers see the same values"
check_var "record_value AQ_RESOLVE_SOURCE" "$(basename "${NASTY_INSTALLER}")" "$(record_value AQ_RESOLVE_SOURCE)"
check_var "record_value AQ_RESOLVE_VERSION" "21.0.4" "$(record_value AQ_RESOLVE_VERSION)"
check_var "record_value AQ_RESOLVE_EDITION" "studio" "$(record_value AQ_RESOLVE_EDITION)"
check_var "updater AQ_RESOLVE_SOURCE" "$(basename "${NASTY_INSTALLER}")" "$(read_py "${RECORD}" AQ_RESOLVE_SOURCE)"
check_var "updater AQ_RESOLVE_VERSION" "21.0.4" "$(read_py "${RECORD}" AQ_RESOLVE_VERSION)"
check_var "updater AQ_RESOLVE_EDITION" "studio" "$(read_py "${RECORD}" AQ_RESOLVE_EDITION)"

# An empty value — the honest answer when the file name does not say — must
# come back empty from every reader, never as two quote marks.
write_record "${RECORD}" "${TMP}/renamed-by-hand.zip" "${NASTY_IMAGE}" "unknown" "cdi"
check_var "record_value of an empty edition" "" "$(record_value AQ_RESOLVE_EDITION)"
check_var "updater's view of an empty edition" "" "$(read_py "${RECORD}" AQ_RESOLVE_EDITION)"
check_var "sourced view of an empty version" "" "$(bash -c 'set -eu; . "$1"; printf %s "${AQ_RESOLVE_VERSION}"' _ "${RECORD}")"

# -----------------------------------------------------------------------------
# 4. A record written before 9 September 2026 still reads
# -----------------------------------------------------------------------------
echo "4. An old, unquoted record still reads"
cat > "${RECORD}" << 'OLD'
# Written by aquarius-resolve-install. Read by 'aq resolve status'
# and by 'aq resolve check'.
AQ_RESOLVE_INSTALLED_AT=2026-09-08T21:14:02-07:00
AQ_RESOLVE_IMAGE=ghcr.io/stoneharborent/aquarius-resolve-runtime:9
AQ_RESOLVE_DIGEST=unknown
AQ_RESOLVE_GPU_METHOD=cdi
AQ_RESOLVE_SOURCE=DaVinci_Resolve_Studio_20.2_Linux.zip
AQ_RESOLVE_EDITION=studio
AQ_RESOLVE_VERSION=20.2
AQ_RESOLVE_VERSION_FROM=the name of the file downloaded from Blackmagic
OLD
check_var "record_value of an old AQ_RESOLVE_VERSION" "20.2" "$(record_value AQ_RESOLVE_VERSION)"
check_var "record_value of an old AQ_RESOLVE_SOURCE" "DaVinci_Resolve_Studio_20.2_Linux.zip" "$(record_value AQ_RESOLVE_SOURCE)"
check_var "updater's view of an old AQ_RESOLVE_VERSION" "20.2" "$(read_py "${RECORD}" AQ_RESOLVE_VERSION)"
check_var "updater's view of the old unquoted sentence" "the name of the file downloaded from Blackmagic" "$(read_py "${RECORD}" AQ_RESOLVE_VERSION_FROM)"

echo ""
if [ "${FAILED}" = "0" ]; then
    echo "test-resolve-record: all good."
    exit 0
fi
echo "test-resolve-record: something above is wrong." >&2
exit 1
