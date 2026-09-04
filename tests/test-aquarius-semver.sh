#!/usr/bin/env bash
# ==============================================================================
# Tests for the version comparison in aquarius-app-overlay
# ==============================================================================
# WHAT THIS IS FOR
# ------------------------------------------------------------------------------
# Aquarius Editor is baked into AquariusOS, and /usr is read-only, so the app
# cannot update itself in place. Instead it downloads a newer copy of itself into
# the user's home folder, and at every launch the OS compares that download's
# version against its own to decide which one to start.
#
# That comparison is the whole ball game. Get it wrong in one direction and a
# genuine update never starts; get it wrong in the other and a machine happily
# runs an old copy forever. And it is easy to get wrong, because the obvious way
# — comparing the version numbers as ordinary text — says that "0.9.0" is newer
# than "0.10.0". This file is a table of known-correct answers that proves it is
# not doing that.
#
# HOW TO RUN IT
# ------------------------------------------------------------------------------
#   ./tests/test-aquarius-semver.sh
#       tests the copy in this repo (system_files/usr/libexec/aquarius-app-overlay)
#
#   ./tests/test-aquarius-semver.sh /usr/libexec/aquarius-app-overlay
#       tests the copy installed in an AquariusOS image. This is what the image
#       build itself runs — see build_files/creator-apps.sh — so a broken
#       comparison stops the build instead of shipping.
#
# It prints a line per case and exits with a failure if any of them is wrong.
# ==============================================================================

set -u

# Where the library is. An argument wins; otherwise use the copy sitting in this
# repo, worked out relative to this script so it does not matter where you run it
# from.
HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="${1:-${HERE}/../system_files/usr/libexec/aquarius-app-overlay}"

if [ ! -r "$LIB" ]; then
    echo "test-aquarius-semver: cannot read the library at ${LIB}" >&2
    exit 1
fi

# The library is a set of functions meant to be read into another script, which
# is what the dot does here.
# shellcheck source=../system_files/usr/libexec/aquarius-app-overlay
. "$LIB"

# Two prerequisites for the whole idea of comparing versions with real
# arithmetic: the shell must be able to do the arithmetic, and the string
# comparison used for pre-releases must not depend on the machine's language
# settings. LC_ALL=C is what makes the second one true everywhere.
export LC_ALL=C

PASSED=0
FAILED=0

# ------------------------------------------------------------------------------
# Is this text a version number at all?
# ------------------------------------------------------------------------------
# Folder names written by the app's updater are BARE version numbers — 0.4.1,
# never v0.4.1 — so anything else has to be rejected. A folder whose name the OS
# cannot read as a version is ignored, which is the safe outcome.
check_valid() {        # check_valid <text> <yes|no> <why this case exists>
    local text="$1" expect="$2" note="$3" got

    if aq_semver_valid "$text"; then got="yes"; else got="no"; fi

    if [ "$got" = "$expect" ]; then
        PASSED=$((PASSED + 1))
        printf '  OK    is "%s" a version number? %-3s  (%s)\n' "$text" "$got" "$note"
    else
        FAILED=$((FAILED + 1))
        printf '  FAIL  is "%s" a version number? got %s, expected %s  (%s)\n' \
            "$text" "$got" "$expect" "$note"
    fi
}

# ------------------------------------------------------------------------------
# Which of two versions is newer?
# ------------------------------------------------------------------------------
# The answer is 1 when the first is newer, -1 when the second is, 0 when they are
# the same version, and the word "invalid" when either one is not a version
# number at all.
check_compare() {      # check_compare <a> <b> <1|0|-1|invalid> <why this case exists>
    local a="$1" b="$2" expect="$3" note="$4" got status

    got="$(aq_semver_compare "$a" "$b")"
    status=$?
    [ "$status" -eq 0 ] || got="invalid"

    if [ "$got" = "$expect" ]; then
        PASSED=$((PASSED + 1))
        printf '  OK    %-16s vs %-16s -> %-7s  (%s)\n' "$a" "$b" "$got" "$note"
    else
        FAILED=$((FAILED + 1))
        printf '  FAIL  %-16s vs %-16s -> %s, expected %s  (%s)\n' \
            "$a" "$b" "$got" "$expect" "$note"
    fi
}

echo "Testing the version comparison in: ${LIB}"
echo
echo "== what counts as a version number =="

check_valid "0.3.0"        yes "the ordinary case"
check_valid "1.12.4"       yes "more than one digit in a part"
check_valid "0.4.0-beta.1" yes "a pre-release"
check_valid "1.2.3+build7" yes "a build tag on the end"
check_valid "0.0.0"        yes "all zeroes is still a version"

check_valid "v0.4.1"       no  "folder names carry no leading v"
check_valid "0.4"          no  "two parts is not enough"
check_valid "0.4.1.2"      no  "four parts is too many"
check_valid ""             no  "nothing at all"
check_valid "latest"       no  "a word, which is what a hand-made folder might be called"
check_valid "0.4.x"        no  "a wildcard is not a version"
check_valid " 0.4.1"       no  "a stray space makes it not a version"
check_valid "0.-1.0"       no  "negative numbers are not versions"
check_valid "1234567890.0.0" no "more than nine digits, which would break the arithmetic"

echo
echo "== which version is newer =="

check_compare "0.4.1" "0.3.0"  1  "a real update"
check_compare "0.3.0" "0.4.1" -1  "the OS is ahead of the download"
check_compare "0.3.0" "0.3.0"  0  "the same version"

# THE ONE THAT MATTERS MOST. Compared as ordinary text, "0.9.0" comes after
# "0.10.0" because the character 9 comes after the character 1. If this case ever
# fails, every machine that reaches version 0.10 stops taking updates.
check_compare "0.10.0" "0.9.0"  1 "TEN beats NINE — the whole reason this is not a text comparison"
check_compare "0.9.0" "0.10.0" -1 "the same trap, the other way round"
check_compare "0.3.10" "0.3.9"  1 "the same trap in the last part"
check_compare "1.0.0" "0.9.9"   1 "a whole new major version"
check_compare "0.9.9" "1.0.0"  -1 "and the other way round"

# Leading zeroes. Some tools write 08 where they mean 8, and a shell that reads
# that as an octal number gives up with an error instead of an answer.
check_compare "08.0.0" "9.0.0" -1 "a leading zero is read as base ten, not octal"
check_compare "1.08.0" "1.9.0" -1 "the same, in the middle part"

# Pre-releases. A beta of 0.4.0 is OLDER than the finished 0.4.0, and still newer
# than everything before it.
check_compare "0.4.0" "0.4.0-beta.1"  1 "the finished version beats its own beta"
check_compare "0.4.0-beta.1" "0.4.0" -1 "and the beta loses to it"
check_compare "0.4.1-beta.1" "0.4.0"  1 "but a beta of a later version still wins"
check_compare "0.4.0-beta.2" "0.4.0-beta.1" 1 "two betas of one version, in order"
check_compare "0.4.0-beta.1" "0.4.0-beta.1" 0 "the same beta twice"

# Anything that is not a version number has no answer, and saying so is the
# point: the launcher treats "no answer" as "do not touch it".
check_compare "latest" "0.3.0"  invalid "a folder called 'latest'"
check_compare "0.3.0" ""        invalid "an empty VERSION file"
check_compare "v0.4.1" "0.3.0"  invalid "a leading v on the download's folder"

echo
echo "== the shorthand the launcher uses =="

# aq_semver_newer is just "is the first strictly newer", and it has to say no —
# not crash, not say yes — when either side is nonsense.
run_newer() {          # run_newer <a> <b> <yes|no> <why>
    local a="$1" b="$2" expect="$3" note="$4" got
    if aq_semver_newer "$a" "$b"; then got="yes"; else got="no"; fi
    if [ "$got" = "$expect" ]; then
        PASSED=$((PASSED + 1))
        printf '  OK    is %-14s newer than %-14s? %-3s  (%s)\n' "$a" "$b" "$got" "$note"
    else
        FAILED=$((FAILED + 1))
        printf '  FAIL  is %-14s newer than %-14s? got %s, expected %s  (%s)\n' \
            "$a" "$b" "$got" "$expect" "$note"
    fi
}

run_newer "0.4.1" "0.3.0" yes "a real update starts"
run_newer "0.3.0" "0.3.0" no  "the same version does not"
run_newer "0.2.0" "0.3.0" no  "an older download does not"
run_newer "latest" "0.3.0" no "and nonsense never does"
run_newer "0.4.1" "" no      "nor does a missing built-in version"

echo
echo "--------------------------------------------------------------"
printf '%d passed, %d failed\n' "$PASSED" "$FAILED"

if [ "$FAILED" -ne 0 ]; then
    echo
    echo "The version comparison is wrong. Do not ship this: Aquarius Editor"
    echo "decides which copy of itself to start with these answers."
    exit 1
fi

echo "The version comparison is correct."
