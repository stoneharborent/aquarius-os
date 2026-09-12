#!/usr/bin/env bash
# ==============================================================================
# Tests for the first-boot Homebrew unpack
# ==============================================================================
# THE FAULT THESE TESTS EXIST TO PREVENT
#
# /usr/libexec/aquarius-brew-setup is started on EVERY boot. That is deliberate:
# it is what lets an AquariusOS update deliver Homebrew to a machine that was
# installed before Homebrew existed. It is only safe because the script's first
# act is to notice that Homebrew is already there and stop.
#
# If that guard ever breaks, here is what happens, and it is nasty because
# nothing reports an error:
#
#   Every boot spends a minute unpacking three hundred megabytes over the top of
#   the Homebrew somebody has been using — wiping everything they installed.
#   The symptom is "my computer takes ages to start and my tools keep
#   disappearing", and there is no failed service, no red text and no log entry
#   that says anything is wrong.
#
# A guard that has never been executed twice is not a guard. These tests execute
# it twice, for real, and check the second run changed nothing.
#
# ------------------------------------------------------------------------------
# HOW THE FAKING WORKS
# ------------------------------------------------------------------------------
# The script reads and writes exactly two places, and both are variables:
#
#   AQ_BREW_ROOT        stands in for /var/home
#   AQ_BREW_BOX         stands in for the packed Homebrew in /usr
#   AQ_BREW_NO_CHOWN=1  skip the ownership step, which this test cannot do
#                       because it is not root
#
# So the test builds a pretend Homebrew in a temporary folder, packs it the same
# way the build does, and points the script at both. Nothing here needs root and
# nothing here touches the machine it runs on.
#
# HOW TO RUN IT
#   ./tests/test-brew-setup.sh
#   ./tests/test-brew-setup.sh /usr/libexec/aquarius-brew-setup   (installed)
# ==============================================================================

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
SETUP="${1:-${HERE}/../system_files/usr/libexec/aquarius-brew-setup}"

if [ ! -r "${SETUP}" ]; then
    echo "test-brew-setup: cannot read ${SETUP}" >&2
    exit 1
fi

export LC_ALL=C

PASSED=0
FAILED=0
pass() {
    echo "  ok   $*"
    PASSED=$((PASSED + 1))
}
fail() {
    echo "  FAIL $*"
    FAILED=$((FAILED + 1))
}

# ------------------------------------------------------------------------------
# Which squeezer this test uses to build its pretend box
# ------------------------------------------------------------------------------
# The real box is squeezed with zstd. The script that unpacks it does NOT name a
# squeezer — tar works that out for itself when reading — so this test does not
# have to use zstd either, and on a machine without the `zstd` program it falls
# back to gzip, which every machine has.
#
# That is not a weaker test: what is being tested is the script's behaviour on
# the second run, which has nothing to do with compression. Step 69 of the build
# is where the real box is proved to be a real zstd archive with a real brew in
# it.
if printf x | tar --zstd -cf /dev/null -T /dev/null > /dev/null 2>&1 \
    && command -v zstd > /dev/null 2>&1; then
    SQUEEZE="--zstd"
    BOX_NAME="homebrew.tar.zst"
else
    echo "  (note: no zstd on this machine, so the pretend box is gzipped instead)"
    SQUEEZE="--gzip"
    BOX_NAME="homebrew.tar.gz"
fi

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# ------------------------------------------------------------------------------
# Build a pretend Homebrew and pack it exactly as build_files/69-homebrew.sh does
# ------------------------------------------------------------------------------
# The shape is what matters, not the contents: one top-level folder called
# `linuxbrew`, containing `.linuxbrew`, containing a runnable `bin/brew`.
SRC="${WORK}/src"
mkdir -p "${SRC}/linuxbrew/.linuxbrew/bin"
mkdir -p "${SRC}/linuxbrew/.linuxbrew/Homebrew/Library"
printf '#!/bin/sh\necho "Homebrew 9.9.9 (pretend)"\n' > "${SRC}/linuxbrew/.linuxbrew/bin/brew"
chmod 0755 "${SRC}/linuxbrew/.linuxbrew/bin/brew"
echo "pretend library" > "${SRC}/linuxbrew/.linuxbrew/Homebrew/Library/marker.txt"

BOX="${WORK}/${BOX_NAME}"
tar -C "${SRC}" "${SQUEEZE}" --sort=name --owner=0 --group=0 --numeric-owner \
    -cf "${BOX}" linuxbrew

ROOT="${WORK}/var-home"
mkdir -p "${ROOT}"

BREW_BIN="${ROOT}/linuxbrew/.linuxbrew/bin/brew"

run_setup() {
    AQ_BREW_ROOT="${ROOT}" \
        AQ_BREW_BOX="${BOX}" \
        AQ_BREW_NO_CHOWN=1 \
        bash "${SETUP}" > "${WORK}/out.txt" 2>&1
}

# ==============================================================================
# 1. The first run really installs it
# ==============================================================================
echo ""
echo "1. The first run puts Homebrew in place"

if run_setup; then
    pass "the first run finished successfully"
else
    fail "the first run failed:"
    sed 's/^/       /' "${WORK}/out.txt"
fi

if [ -x "${BREW_BIN}" ]; then
    pass "brew is at ${BREW_BIN#"${WORK}/"} and is runnable"
else
    fail "brew is not there after the first run — nothing was unpacked"
fi

# The whole tree, not just the one file. A brew launcher with no library behind
# it is a command that fails on its first use.
if [ -r "${ROOT}/linuxbrew/.linuxbrew/Homebrew/Library/marker.txt" ]; then
    pass "the rest of the tree came with it, not just bin/brew"
else
    fail "only part of the box was unpacked"
fi

# And it actually runs, which is the difference between "a file is there" and
# "Homebrew is installed".
if "${BREW_BIN}" 2>&1 | grep -q 'pretend'; then
    pass "the unpacked brew runs"
else
    fail "the unpacked brew does not run"
fi

# ==============================================================================
# 2. ⚠️ THE TEST THIS FILE EXISTS FOR: the second run must change NOTHING
# ==============================================================================
echo ""
echo "2. The second run changes nothing (this is the one that matters)"

# Put a fingerprint in the tree — the stand-in for "a tool somebody installed".
# If the second run unpacks over the top, this is gone, which is exactly the
# damage we are testing for.
echo "a tool the person installed" > "${ROOT}/linuxbrew/.linuxbrew/bin/my-own-tool"

# And change brew itself, so that an overwrite is detectable even if the extra
# file somehow survived.
printf '#!/bin/sh\necho "EDITED BY THE PERSON"\n' > "${BREW_BIN}"
chmod 0755 "${BREW_BIN}"

if run_setup; then
    pass "the second run finished successfully"
else
    fail "the second run failed:"
    sed 's/^/       /' "${WORK}/out.txt"
fi

if [ -r "${ROOT}/linuxbrew/.linuxbrew/bin/my-own-tool" ]; then
    pass "a tool the person installed is still there"
else
    fail "the second run WIPED a tool the person installed — this is the fault this file exists for"
fi

if "${BREW_BIN}" 2>&1 | grep -q 'EDITED BY THE PERSON'; then
    pass "the person's own brew was left alone"
else
    fail "the second run overwrote the existing Homebrew — every boot would do this"
fi

# It should say so, too. A script that does nothing and says nothing is
# indistinguishable from one that crashed instantly.
if grep -qi 'already installed' "${WORK}/out.txt"; then
    pass "it says out loud that there was nothing to do"
else
    fail "the second run said nothing about why it did nothing:"
    sed 's/^/       /' "${WORK}/out.txt"
fi

# ==============================================================================
# 3. It leaves no mess behind
# ==============================================================================
echo ""
echo "3. No half-unpacked leftovers"

# The script unpacks into a staging folder and renames it. If a staging folder
# survives, every boot leaks a few hundred megabytes into /var until the disk
# fills up — which looks like anything except this.
LEFTOVERS="$(find "${ROOT}" -maxdepth 1 -name '.linuxbrew-unpacking.*' | wc -l | tr -d ' ')"
if [ "${LEFTOVERS}" -eq 0 ]; then
    pass "no staging folders were left in place"
else
    fail "${LEFTOVERS} staging folder(s) left behind — every boot would leak one"
fi

# ==============================================================================
# 4. A machine with no box, and a machine with a broken box
# ==============================================================================
echo ""
echo "4. The two things that can be wrong with the box"

EMPTY_ROOT="${WORK}/empty-root"
mkdir -p "${EMPTY_ROOT}"

# No box at all. This must be a quiet no-op, not a failure: it is what a machine
# looks like if somebody deletes the box, and a boot must not be affected.
if AQ_BREW_ROOT="${EMPTY_ROOT}" AQ_BREW_BOX="${WORK}/there-is-no-such-file" \
    AQ_BREW_NO_CHOWN=1 bash "${SETUP}" > "${WORK}/nobox.txt" 2>&1; then
    pass "no box at all is a quiet no-op, not a failed boot"
else
    fail "a missing box made the script fail — that would show as a failed service at every boot"
    sed 's/^/       /' "${WORK}/nobox.txt"
fi

# A box that is a valid archive of the wrong thing. This MUST fail loudly and
# MUST NOT leave a broken Homebrew at the real path, because the guard in part 2
# would then decide forever that the machine already has one.
BAD_SRC="${WORK}/bad-src"
mkdir -p "${BAD_SRC}/linuxbrew/.linuxbrew"
echo "nothing useful" > "${BAD_SRC}/linuxbrew/.linuxbrew/README"
BAD_BOX="${WORK}/bad.tar${BOX_NAME#homebrew.tar}"
tar -C "${BAD_SRC}" "${SQUEEZE}" -cf "${BAD_BOX}" linuxbrew

BAD_ROOT="${WORK}/bad-root"
mkdir -p "${BAD_ROOT}"
if AQ_BREW_ROOT="${BAD_ROOT}" AQ_BREW_BOX="${BAD_BOX}" \
    AQ_BREW_NO_CHOWN=1 bash "${SETUP}" > "${WORK}/badbox.txt" 2>&1; then
    fail "a box with no brew in it was reported as a success"
else
    pass "a box with no brew in it is refused"
fi
if [ -e "${BAD_ROOT}/linuxbrew" ]; then
    fail "a broken box left a half-Homebrew in place — the guard would skip the repair forever"
else
    pass "a broken box installs nothing at all, so the next boot tries again"
fi

# ==============================================================================
# 5. The paths, read out of the script itself
# ==============================================================================
echo ""
echo "5. Nothing in the script is hard-coded past the two knobs"

# Every path the script touches must be built from AQ_BREW_ROOT or AQ_BREW_BOX,
# or this test has been proving nothing about the real thing.
if grep -qE '^AQ_BREW_DIR="\$\{AQ_BREW_ROOT\}' "${SETUP}"; then
    pass "the install folder is built from AQ_BREW_ROOT, so a test cannot touch the real machine"
else
    fail "the install folder is hard-coded — a test would write to the real /var/home"
fi

# The default must still be the real place, or the image ships a script that
# unpacks Homebrew into nowhere.
if grep -qF 'AQ_BREW_ROOT:-/var/home' "${SETUP}"; then
    pass "with no knobs set it uses /var/home, the real place"
else
    fail "the default install location is not /var/home"
fi
if grep -qF 'AQ_BREW_BOX:-/usr/share/aquarius/homebrew/homebrew.tar.zst' "${SETUP}"; then
    pass "with no knobs set it reads the real box in /usr"
else
    fail "the default box path is not the one build_files/69-homebrew.sh writes"
fi

# The ownership model, stated in the script rather than assumed by this test.
if grep -qF 'AQ_BREW_GROUP="wheel"' "${SETUP}"; then
    pass "it hands the folder to the wheel group (the people who administer this computer)"
else
    fail "the group the folder is handed to is no longer wheel — update docs/restart/homebrew.md too"
fi

echo ""
echo "  passed ${PASSED}, failed ${FAILED}"
if [ "${FAILED}" -ne 0 ]; then
    echo "  The first-boot Homebrew unpack would not behave. The dangerous case is"
    echo "  part 2: a machine that re-unpacks Homebrew at every boot wipes whatever"
    echo "  the person installed, silently. See docs/restart/homebrew.md."
    exit 1
fi
echo "  Homebrew is unpacked once, never twice, and a broken box installs nothing."
exit 0
