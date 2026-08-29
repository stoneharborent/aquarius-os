#!/usr/bin/env bash
# ==============================================================================
# Tests for "which copy of the app should start?"
# ==============================================================================
# The companion test file, test-aquarius-semver.sh, checks that the version
# comparison gives the right numbers. This one checks what the launcher DOES with
# those numbers, which is a different question and the one that decides whether
# somebody's app opens.
#
# Every test builds a complete little pretend world in a temporary folder — a
# pretend built-in app, a pretend home directory, pretend downloaded updates —
# runs the real function against it, and then looks at two things: which folder
# it chose, and what it deleted.
#
# THE RULES BEING TESTED, in the order they matter:
#
#   1. A downloaded update starts ONLY if its version is genuinely newer.
#   2. Anything broken out there — a link to nothing, a nonsense folder name, an
#      app with no runnable AppRun — ends with the built-in copy starting. Never
#      with nothing starting.
#   3. Downloads the OS has caught up with get deleted (they are ~2 GB each).
#   4. NOTHING is EVER deleted while the download is the newer one.
#
# HOW TO RUN IT
#   ./tests/test-aquarius-overlay.sh
#   ./tests/test-aquarius-overlay.sh /usr/libexec/aquarius-app-overlay
# ==============================================================================

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="${1:-${HERE}/../system_files/usr/libexec/aquarius-app-overlay}"

if [ ! -r "$LIB" ]; then
    echo "test-aquarius-overlay: cannot read the library at ${LIB}" >&2
    exit 1
fi

# shellcheck source=../system_files/usr/libexec/aquarius-app-overlay
. "$LIB"

export LC_ALL=C

APP_ID="aquarius-editor"
PASSED=0
FAILED=0

# Somewhere to build the pretend worlds. `readlink -f` at the end matters: on
# some systems the temporary folder is itself a link, and the library checks that
# what it is about to delete really is inside the home folder it was given.
WORK="$(mktemp -d)"
WORK="$(readlink -f "$WORK")"
cleanup_work() { rm -rf -- "$WORK"; }
trap cleanup_work EXIT

pass() { PASSED=$((PASSED + 1)); printf '  OK    %s\n' "$1"; }
fail() { FAILED=$((FAILED + 1)); printf '  FAIL  %s\n' "$1"; }

# ------------------------------------------------------------------------------
# Building a pretend world
# ------------------------------------------------------------------------------
# make_app <folder> <runnable: yes|no>
#   A folder shaped like an unpacked AppImage: an AppRun at the top, and the
#   Electron program next to it. "no" leaves AppRun there but not runnable, which
#   is one of the ways a half-finished download looks.
make_app() {
    local dir="$1" runnable="$2"
    mkdir -p "$dir"
    printf '#!/bin/sh\nexit 0\n' >"${dir}/AppRun"
    printf '#!/bin/sh\nexit 0\n' >"${dir}/${APP_ID}"
    if [ "$runnable" = "yes" ]; then
        chmod 0755 "${dir}/AppRun" "${dir}/${APP_ID}"
    else
        chmod 0644 "${dir}/AppRun" "${dir}/${APP_ID}"
    fi
}

# new_world <name> <version to write in the built-in app's VERSION file>
#   Sets HOME, BAKED_ROOT and OVERLAY for the test about to run. Pass the empty
#   string as the version to leave the VERSION file out altogether.
new_world() {
    local name="$1" baked_version="$2"
    HOME="${WORK}/${name}/home"
    BAKED_ROOT="${WORK}/${name}/usr"
    OVERLAY="${HOME}/.local/share/aquarius/${APP_ID}"
    export HOME

    mkdir -p "$HOME" "${OVERLAY}/versions"
    make_app "${BAKED_ROOT}/${APP_ID}" yes
    if [ -n "$baked_version" ]; then
        printf '%s\n' "$baked_version" >"${BAKED_ROOT}/${APP_ID}/VERSION"
    fi
}

# add_download <version> [runnable]
#   A copy the app "downloaded" into the home folder.
add_download() {
    make_app "${OVERLAY}/versions/$1" "${2:-yes}"
}

# point_current_at <folder name under versions/>
point_current_at() {
    ln -sfn "versions/$1" "${OVERLAY}/current"
}

# run_prepare
#   The real function, against the pretend world.
run_prepare() {
    AQ_INSTALL_ROOT=""
    AQ_LAUNCH_NOTES=""
    aq_overlay_prepare "$APP_ID" "$BAKED_ROOT"
}

# ------------------------------------------------------------------------------
# Asking what happened
# ------------------------------------------------------------------------------
expect_starts_builtin() {   # expect_starts_builtin <what this test is about>
    if [ "$AQ_INSTALL_ROOT" = "${BAKED_ROOT}/${APP_ID}" ]; then
        pass "$1 — starts the copy built into AquariusOS"
    else
        fail "$1 — expected the built-in copy, got '${AQ_INSTALL_ROOT}'"
    fi
}

expect_starts_download() {  # expect_starts_download <version> <what this is about>
    if [ "$AQ_INSTALL_ROOT" = "${OVERLAY}/versions/$1" ]; then
        pass "$2 — starts the downloaded ${1}"
    else
        fail "$2 — expected the downloaded ${1}, got '${AQ_INSTALL_ROOT}'"
    fi
}

expect_kept() {             # expect_kept <version> <what this is about>
    if [ -d "${OVERLAY}/versions/$1" ]; then
        pass "$2 — kept the downloaded ${1}"
    else
        fail "$2 — the downloaded ${1} was DELETED and should not have been"
    fi
}

expect_deleted() {          # expect_deleted <version> <what this is about>
    if [ ! -e "${OVERLAY}/versions/$1" ]; then
        pass "$2 — deleted the superseded ${1}"
    else
        fail "$2 — the superseded ${1} is still taking up space"
    fi
}

expect_no_current_link() {  # expect_no_current_link <what this is about>
    if [ ! -L "${OVERLAY}/current" ]; then
        pass "$1 — cleared away the leftover 'current' link"
    else
        fail "$1 — a 'current' link pointing at nothing was left behind"
    fi
}

expect_note_mentions() {    # expect_note_mentions <text> <what this is about>
    case "$AQ_LAUNCH_NOTES" in
        *"$1"*) pass "$2 — the log will say so" ;;
        *)      fail "$2 — nothing in the log mentions '$1'. Log says: ${AQ_LAUNCH_NOTES}" ;;
    esac
}

echo "Testing the copy-choosing logic in: ${LIB}"
echo

# ==============================================================================
echo "== nothing has ever been downloaded =="
new_world plain 0.3.0
run_prepare
expect_starts_builtin "a machine that has never updated the app"
expect_note_mentions "0.3.0" "the built-in version is named in the log"

# ==============================================================================
echo
echo "== a genuinely newer download =="
new_world newer 0.3.0
add_download 0.4.1
point_current_at 0.4.1
run_prepare
expect_starts_download 0.4.1 "an update newer than the OS"
expect_kept 0.4.1 "the copy it is about to start"
expect_note_mentions "STARTING THE DOWNLOADED UPDATE" "which copy won"

# RULE 4, THE IMPORTANT ONE. An older download sitting next to a newer one is
# still not to be touched while the newer one is what starts. Cleaning up is only
# ever done on the way past, when the OS itself is ahead.
new_world newer_with_old 0.3.0
add_download 0.2.0
add_download 0.4.1
point_current_at 0.4.1
run_prepare
expect_starts_download 0.4.1 "an update newer than the OS, with an old one lying about"
expect_kept 0.2.0 "nothing at all is deleted while the download is ahead"

# ==============================================================================
echo
echo "== the OS has caught up =="
new_world equal 0.4.1
add_download 0.4.1
point_current_at 0.4.1
run_prepare
expect_starts_builtin "the same version in both places"
expect_deleted 0.4.1 "a download the OS now matches"
expect_no_current_link "the link that pointed at it"

new_world older 0.5.0
add_download 0.4.1
add_download 0.2.0
point_current_at 0.4.1
run_prepare
expect_starts_builtin "an OS newer than the download"
expect_deleted 0.4.1 "the download the OS overtook"
expect_deleted 0.2.0 "and the one before that"

# The trap that a plain text comparison falls into. 0.9.0 must NOT be treated as
# newer than 0.10.0, or this machine deletes a real update and never starts one
# again.
new_world ten_vs_nine 0.9.0
add_download 0.10.0
point_current_at 0.10.0
run_prepare
expect_starts_download 0.10.0 "0.10.0 against a built-in 0.9.0"
expect_kept 0.10.0 "the real update is not mistaken for an old one"

# ==============================================================================
echo
echo "== broken downloads never stop the app =="

# A link pointing at a folder that is not there any more.
new_world dangling 0.3.0
ln -sfn "versions/0.4.1" "${OVERLAY}/current"
run_prepare
expect_starts_builtin "a 'current' link pointing at nothing"
expect_no_current_link "the dead link"

# A folder whose name is not a version number. We cannot compare it to anything,
# so we leave it alone entirely — not started, not deleted.
new_world nonsense 0.3.0
make_app "${OVERLAY}/versions/latest" yes
point_current_at latest
run_prepare
expect_starts_builtin "a download in a folder called 'latest'"
expect_kept latest "a folder we cannot read the version of is not ours to delete"

# Newer, but there is nothing runnable in it — a download that was interrupted,
# or unpacked without its permissions. This is the case that must never turn into
# a dead icon.
new_world unrunnable 0.3.0
add_download 0.4.1 no
point_current_at 0.4.1
run_prepare
expect_starts_builtin "a newer download with no runnable AppRun"
expect_kept 0.4.1 "and it is kept, not destroyed, so it can be looked at"
expect_note_mentions "not marked as runnable" "why it was passed over"

# No VERSION file in the built-in app. Nothing can be compared, so nothing is
# started from the overlay and — just as importantly — nothing is deleted.
new_world noversion ""
add_download 0.1.0
point_current_at 0.1.0
run_prepare
expect_starts_builtin "an OS with no VERSION file"
expect_kept 0.1.0 "nothing is deleted when there is nothing to compare against"

# ==============================================================================
echo
echo "== what the app is told =="
new_world contract 0.3.0
run_prepare
if [ "${AQUARIUS_OS_MANAGED_INSTALL:-}" = "1" ]; then
    pass "the app is told this is an OS-managed install"
else
    fail "AQUARIUS_OS_MANAGED_INSTALL was not set to 1"
fi
if [ "${AQUARIUS_UPDATE_OVERLAY_DIR:-}" = "$OVERLAY" ]; then
    pass "the app is told where it may write updates (${OVERLAY})"
else
    fail "AQUARIUS_UPDATE_OVERLAY_DIR is '${AQUARIUS_UPDATE_OVERLAY_DIR:-}', expected '${OVERLAY}'"
fi

echo
echo "--------------------------------------------------------------"
printf '%d passed, %d failed\n' "$PASSED" "$FAILED"

if [ "$FAILED" -ne 0 ]; then
    echo
    echo "The launcher would start the wrong copy of Aquarius Editor, or delete"
    echo "something it should not. Do not ship this."
    exit 1
fi

echo "The launcher chooses correctly."
