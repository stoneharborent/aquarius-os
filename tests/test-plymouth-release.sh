#!/usr/bin/bash
# =============================================================================
# test-plymouth-release.sh — the boot animation always goes away
# =============================================================================
# WHAT THIS PROVES, AND WHY IT IS WORTH A TEST OF ITS OWN
#
# AquariusOS's own greetd.service says `Conflicts=plymouth-quit.service`. That
# single line stops Fedora's "take the boot animation away" service running at
# all on a boot that uses our login screen — which is what lets the animation
# stay up until the login screen can appear over it, the way a Mac hands one
# picture to the next.
#
# It also means that from that moment on, ONE program is responsible for ever
# taking the animation down: /usr/libexec/aquarius-plymouth-release. If it fails
# to, the machine sits on a still picture of the Aquarius mark with no way in
# and no explanation. That is the worst outcome this repository can produce, so
# it is tested against a stand-in `plymouth` that writes down every request.
#
# The five cases:
#
#   1. No boot animation is running (a machine booted without one, or a build
#      container). It must exit at once and ask for nothing.
#   2. The login screen has drawn. It must ask for `quit --retain-splash`, which
#      is the one that keeps the picture so the login screen appears over it.
#   3. ⚠️ THE LOAD-BEARING ONE. The login screen never draws. It must STILL take
#      the animation down when its time runs out — and NOT keep the picture,
#      because whatever is underneath (a text login, an error) has to be
#      visible.
#   4. No stamp, but Quickshell is alive — the weaker of the two signals is
#      still accepted, because it is the one the machine runs on today.
#   5. --status only looks. And whatever happens, every path exits 0: a failure
#      here must never mark the boot as failed.
#
# HOW TO RUN IT
#   ./tests/test-plymouth-release.sh
#   ./tests/test-plymouth-release.sh /usr/libexec/aquarius-plymouth-release
# =============================================================================

set -uo pipefail

PROG="${1:-}"
if [ -z "${PROG}" ]; then
    PROG="$(cd "$(dirname "$0")/.." && pwd)/system_files/usr/libexec/aquarius-plymouth-release"
fi

if [ ! -r "${PROG}" ]; then
    echo "FAIL ${PROG} is not there — nothing to test." >&2
    exit 1
fi

fails=0
ok() { echo "  OK   $*"; }
bad() {
    echo "  FAIL $*" >&2
    fails=$((fails + 1))
}

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# -----------------------------------------------------------------------------
# The stand-in plymouth
# -----------------------------------------------------------------------------
# It answers `--ping` according to ${WORK}/running, and writes every other
# request into ${WORK}/asked, one per line. That file is the whole evidence.
cat > "${WORK}/plymouth" <<'STANDIN'
#!/usr/bin/bash
if [ "${1:-}" = "--ping" ]; then
    [ -e "${AQ_TEST_RUNNING}" ] && exit 0
    exit 1
fi
printf '%s\n' "$*" >> "${AQ_TEST_ASKED}"
exit 0
STANDIN
chmod 0755 "${WORK}/plymouth"

export AQ_TEST_RUNNING="${WORK}/running"
export AQ_TEST_ASKED="${WORK}/asked"
export AQ_PLYMOUTH_CMD="${WORK}/plymouth"

# -----------------------------------------------------------------------------
# The stand-in pgrep
# -----------------------------------------------------------------------------
# ⚠️ THIS IS NOT OPTIONAL, AND THE REASON IS FUNNY. The program's second signal
# is "is Quickshell running?" — and this test is often run ON a machine whose
# desktop IS Quickshell. Without a stand-in, the real pgrep answers "yes, the
# login screen has drawn" on every single case, and the test that matters most
# (the login screen never draws) can never fail.
mkdir -p "${WORK}/bin"
cat > "${WORK}/bin/pgrep" <<'STANDIN'
#!/usr/bin/bash
[ -e "${AQ_TEST_QS_RUNNING}" ] && { echo 1234; exit 0; }
exit 1
STANDIN
chmod 0755 "${WORK}/bin/pgrep"
export AQ_TEST_QS_RUNNING="${WORK}/qs-running"
PATH="${WORK}/bin:${PATH}"
export PATH

# The stamps the program looks for live under /run on a real machine. Pointing
# AQ_PLYMOUTH_RELEASE_ROOT at a temporary folder moves them there instead — the
# same test hook aquarius-greeter-watchdog has, for the same reason.
export AQ_PLYMOUTH_RELEASE_ROOT="${WORK}/fake"
mkdir -p "${WORK}/fake/run/aquarius-greeter"
READY="${WORK}/fake/run/aquarius-greeter/ready"

reset() {
    : > "${AQ_TEST_ASKED}"
    rm -f "${READY}" "${AQ_TEST_QS_RUNNING}"
}

asked() { cat "${AQ_TEST_ASKED}" 2> /dev/null; }

echo "== the boot animation always goes away =="
echo "   program under test: ${PROG}"

# -----------------------------------------------------------------------------
# 1. Nothing to hand over
# -----------------------------------------------------------------------------
reset
rm -f "${AQ_TEST_RUNNING}"
if "${PROG}" > "${WORK}/out" 2>&1; then
    if [ ! -s "${AQ_TEST_ASKED}" ]; then
        ok "with no boot animation running it asks for nothing and exits 0"
    else
        bad "with no boot animation running it still asked for: $(asked)"
    fi
else
    bad "it exited non-zero when there was no boot animation to take down"
fi

# -----------------------------------------------------------------------------
# 2. The login screen drew — keep the picture
# -----------------------------------------------------------------------------
# The stamp is the strongest signal, and it is the one the shell's greeter is
# being taught to write.
reset
: > "${AQ_TEST_RUNNING}"
: > "${READY}"
if AQ_PLYMOUTH_RELEASE_WAIT=3 "${PROG}" > "${WORK}/out" 2>&1; then
    if asked | grep -q -- 'quit --retain-splash'; then
        ok "when the login screen has drawn it keeps the last frame (quit --retain-splash)"
    else
        bad "the login screen had drawn but it did not ask for 'quit --retain-splash'. It asked: $(asked)"
    fi
else
    bad "it exited non-zero on the healthy path"
fi

# -----------------------------------------------------------------------------
# 3. ⚠️ The login screen never drew — take it down anyway, and clear it
# -----------------------------------------------------------------------------
reset
: > "${AQ_TEST_RUNNING}"
start="$(date +%s)"
if AQ_PLYMOUTH_RELEASE_WAIT=2 AQ_PLYMOUTH_RELEASE_POLL=0.2 \
    "${PROG}" > "${WORK}/out" 2>&1; then
    took=$(($(date +%s) - start))
    if asked | grep -qx 'quit'; then
        ok "when the login screen never draws it still takes the animation down"
    else
        bad "the login screen never drew and the animation was NOT taken down. It asked: $(asked)"
    fi
    if asked | grep -q -- 'quit --retain-splash'; then
        bad "it kept the last frame on the failure path — the machine would show a picture and nothing else"
    else
        ok "and it does NOT keep the last frame, so whatever is underneath can be seen"
    fi
    if [ "${took}" -ge 2 ] && [ "${took}" -le 12 ]; then
        ok "it waited for the login screen before giving up (${took}s)"
    else
        bad "it gave up after ${took}s, which is not the wait it was given"
    fi
    if grep -q 'did not draw' "${WORK}/out"; then
        ok "and it says so in the journal, in plain words"
    else
        bad "it gave up silently — nothing in the log would explain the boot"
    fi
else
    bad "it exited non-zero when the login screen did not draw — that would mark the boot failed"
fi

# -----------------------------------------------------------------------------
# 4. No stamp, but Quickshell is alive — the weaker signal still counts
# -----------------------------------------------------------------------------
# This is the signal the machine actually runs on today, because the greeter QML
# does not write the stamp yet. If it stopped being accepted, every greetd boot
# would sit through the full timeout and then clear the screen.
reset
: > "${AQ_TEST_RUNNING}"
: > "${AQ_TEST_QS_RUNNING}"
if AQ_PLYMOUTH_RELEASE_WAIT=3 "${PROG}" > "${WORK}/out" 2>&1; then
    if asked | grep -q -- 'quit --retain-splash'; then
        ok "a running Quickshell is accepted as 'the login screen drew'"
    else
        bad "Quickshell was running and it did not hand the screen over. It asked: $(asked)"
    fi
else
    bad "it exited non-zero with Quickshell running"
fi

# -----------------------------------------------------------------------------
# 5. --status changes nothing
# -----------------------------------------------------------------------------
reset
: > "${AQ_TEST_RUNNING}"
if "${PROG}" --status > "${WORK}/out" 2>&1; then
    if [ ! -s "${AQ_TEST_ASKED}" ]; then
        ok "--status only looks; it never takes the animation down"
    else
        bad "--status asked plymouth for: $(asked)"
    fi
else
    bad "--status exited non-zero"
fi

echo ""
if [ "${fails}" -ne 0 ]; then
    echo "::error::The boot-animation handover is not safe (${fails} check(s) failed)."
    echo "A machine could be left showing the boot animation with no way in."
    echo "See docs/restart/boot-branding.md and docs/restart/login.md."
    exit 1
fi
echo "All boot-animation handover checks passed."
