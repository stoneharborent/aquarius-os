#!/usr/bin/env bash
# ==============================================================================
# Tests for the watchdog that switches back to GDM when the Aquarius greeter
# never draws
# ==============================================================================
# THE BUG THESE TESTS EXIST FOR
#
# 2026-09-05. Royce ran `aq login use greetd` (the R5 greeter test) and the
# machine black-screened for days. greetd started labwc, the Quickshell greeter
# never drew, and every reboot came back to the same bare labwc desktop (the one
# whose only feature is a Terminal / Reconfigure / Exit menu). The marker that
# switched greetd on persisted across every reboot, so the machine could not get
# itself out. The only fix was a text console and a manual switch back to GDM.
#
# The rule that came out of it: it must be IMPOSSIBLE to stay stuck behind our
# own experimental greeter. /usr/libexec/aquarius-greeter-watchdog is that rule.
# After two failed greetd boots in a row it switches the machine back to GDM and
# reboots. A safety net whose trigger has never been executed is not a safety
# net; it is a comment. These tests execute it, both branches, with fakes.
#
# ------------------------------------------------------------------------------
# HOW THE FAKING WORKS
# ------------------------------------------------------------------------------
# The watchdog talks to the machine through three commands, each replaced here
# with a small script on PATH that answers from files in a temporary folder:
#
#   systemctl   is greetd the login screen; and it RECORDS any disable/enable/
#               reboot the watchdog asks for instead of doing one
#   pgrep       is Quickshell (qs) running
#   sleep       returns instantly, so the 30-second watch takes no time
#
# Everything else — the counter, the decision, the revert bookkeeping — is the
# real program. AQ_GREETER_WATCHDOG_ROOT puts every path it touches inside the
# temporary folder, so this runs as an ordinary user and changes nothing.
#
# HOW TO RUN IT
#   ./tests/test-greeter-watchdog.sh
#   ./tests/test-greeter-watchdog.sh /usr/libexec/aquarius-greeter-watchdog   (installed)
# ==============================================================================

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
WD="${1:-${HERE}/../system_files/usr/libexec/aquarius-greeter-watchdog}"

if [ ! -r "${WD}" ]; then
    echo "test-greeter-watchdog: cannot read ${WD}" >&2
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

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# ------------------------------------------------------------------------------
# The fake commands
# ------------------------------------------------------------------------------
make_stubs() {
    mkdir -p "${WORK}/bin"

    # systemctl. is-enabled answers from marker files; disable/enable/reboot are
    # written down rather than performed.
    cat > "${WORK}/bin/systemctl" << 'STUB'
#!/usr/bin/env bash
d="${AQ_STUB_DIR}"
case "${1:-}" in
  is-enabled)
    case "${2:-}" in
      greetd.service) [ -e "${d}/greetd-enabled" ] && exit 0 || exit 1 ;;
      gdm.service)    [ -e "${d}/gdm-enabled" ]    && exit 0 || exit 1 ;;
    esac
    exit 1
    ;;
  disable|enable|reboot|restart|start|stop)
    echo "$*" >> "${d}/actions"
    exit 0
    ;;
esac
exit 0
STUB

    # pgrep. `qs` is alive only if the case says so.
    cat > "${WORK}/bin/pgrep" << 'STUB'
#!/usr/bin/env bash
d="${AQ_STUB_DIR}"
# args look like: -x qs   /   -x quickshell
name="${!#}"
case "${name}" in
  qs)         [ -e "${d}/qs-alive" ] && exit 0 || exit 1 ;;
  quickshell) [ -e "${d}/quickshell-alive" ] && exit 0 || exit 1 ;;
esac
exit 1
STUB

    printf '#!/usr/bin/env bash\nexit 0\n' > "${WORK}/bin/sleep"

    chmod 0755 "${WORK}/bin/"*
}
make_stubs

# ------------------------------------------------------------------------------
# scenario <name> — a machine for the watchdog to look at
# ------------------------------------------------------------------------------
# Every scenario starts the same way: greetd IS the login screen, the greeter is
# NOT healthy (no qs, no ready stamp), the counter is 0, greetd is on probation.
# A case then changes one thing — the difference IS the test.
ROOT=""
STUBS=""
scenario() {
    ROOT="${WORK}/$1/root"
    STUBS="${WORK}/$1/stubs"
    mkdir -p "${ROOT}/var/lib/aquarius" "${ROOT}/run/aquarius" "${STUBS}"
    : > "${STUBS}/greetd-enabled"          # greetd is the login screen
    printf '0\n' > "${ROOT}/var/lib/aquarius/greeter-fails"
    : > "${ROOT}/var/lib/aquarius/greeter-probation"
}

run_watchdog() {
    AQ_GREETER_WATCHDOG_ROOT="${ROOT}" \
        AQ_GREETER_WATCHDOG_FIRST_LOOK=0 \
        AQ_GREETER_WATCHDOG_POLL_EVERY=1 \
        AQ_GREETER_WATCHDOG_TOTAL_WAIT=2 \
        AQ_STUB_DIR="${STUBS}" \
        PATH="${WORK}/bin:${PATH}" \
        bash "${WD}" > "${ROOT}/said.txt" 2>&1
}

set_counter() { printf '%s\n' "$1" > "${ROOT}/var/lib/aquarius/greeter-fails"; }
counter() { tr -cd '0-9' < "${ROOT}/var/lib/aquarius/greeter-fails" 2> /dev/null; }
reverted() { [ -e "${STUBS}/actions" ] && grep -q 'reboot' "${STUBS}/actions"; }
gdm_enabled() { [ -e "${STUBS}/actions" ] && grep -q 'enable gdm.service' "${STUBS}/actions"; }
greetd_disabled() { [ -e "${STUBS}/actions" ] && grep -q 'disable greetd.service' "${STUBS}/actions"; }
probation_gone() { [ ! -e "${ROOT}/var/lib/aquarius/greeter-probation" ]; }

# ==============================================================================
echo "== a greeter that comes up must reset the counter and never revert =="
# ==============================================================================
# This is the case that has to be right first: switching a healthy machine back
# to GDM out from under somebody is the worst thing this program could do.
scenario healthy
set_counter 1                     # even after an earlier bad boot...
: > "${STUBS}/qs-alive"           # ...Quickshell is up this time
run_watchdog
rc=$?
if [ "${rc}" -ne 0 ]; then
    fail "the watchdog failed on a healthy machine (it must always exit cleanly)"
    sed 's/^/       /' "${ROOT}/said.txt"
elif reverted; then
    fail "it switched a healthy machine back to GDM"
    sed 's/^/       /' "${ROOT}/said.txt"
elif [ "$(counter)" != "0" ]; then
    fail "the greeter came up but the counter was not reset (it is $(counter))"
elif ! probation_gone; then
    fail "the greeter came up but probation was not cleared"
else
    pass "Quickshell was running: counter reset to 0, probation cleared, no revert"
fi

# The ready stamp is the stronger signal, and must reset even with no qs process.
#
# ⚠️ THERE ARE TWO PATHS, AND BOTH ARE TESTED (2026-09-08). /run belongs to root
# and the login screen runs as the unprivileged `greetd` user, so the greeter
# CANNOT create /run/aquarius-greeter-ready — the path the documentation asked
# it to write for three days. greetd.service now makes /run/aquarius-greeter and
# gives it to that user, so the stamp the greeter can really write is
# /run/aquarius-greeter/ready. The old path still counts, because anything
# running as root can write it.
scenario healthy-by-ready-stamp
set_counter 1
: > "${ROOT}/run/aquarius-greeter-ready"     # the greeter said "I drew"
run_watchdog
if reverted; then
    fail "the greeter posted its ready stamp and it reverted anyway"
elif [ "$(counter)" != "0" ]; then
    fail "the ready stamp was present but the counter was not reset"
else
    pass "the ready stamp alone (no qs process) is enough to count as healthy"
fi

scenario healthy-by-writable-ready-stamp
set_counter 1
mkdir -p "${ROOT}/run/aquarius-greeter"
: > "${ROOT}/run/aquarius-greeter/ready"     # the path the greeter can write
run_watchdog
if reverted; then
    fail "the greeter posted /run/aquarius-greeter/ready and it reverted anyway"
elif [ "$(counter)" != "0" ]; then
    fail "/run/aquarius-greeter/ready was present but the counter was not reset"
else
    pass "the stamp the greeter can actually write (/run/aquarius-greeter/ready) counts too"
fi

# ==============================================================================
echo ""
echo "== one failed greetd boot warns but does NOT revert =="
# ==============================================================================
# A single odd boot is not a pattern. It records the failure and waits.
scenario one-failure
set_counter 0                     # first bad boot
run_watchdog
if reverted; then
    fail "it switched back to GDM after only ONE failed boot"
    sed 's/^/       /' "${ROOT}/said.txt"
elif [ "$(counter)" != "1" ]; then
    fail "one failed boot should leave the counter at 1, it is $(counter)"
else
    pass "one failed boot: counter goes to 1, no revert, a warning is logged"
fi

# ==============================================================================
echo ""
echo "== ⚠️ THE 2026-09-05 CASE: a second failed greetd boot reverts to GDM =="
# ==============================================================================
# The greeter did not draw, again. This is the boot that must rescue the machine.
scenario two-failures
set_counter 1                     # one bad boot already behind us
run_watchdog                      # ...this makes two
if ! reverted; then
    fail "THE 2026-09-05 BUG WOULD BE BACK: two failed boots and it did not revert"
    sed 's/^/       /' "${ROOT}/said.txt"
elif ! gdm_enabled; then
    fail "it 'reverted' but never switched GDM on"
elif ! greetd_disabled; then
    fail "it 'reverted' but never switched greetd off — two login managers is a black screen"
elif [ "$(counter)" != "0" ]; then
    fail "after reverting, the counter must be 0 so the GDM boot is clean (it is $(counter))"
elif ! probation_gone; then
    fail "after reverting, probation must be cleared"
else
    pass "two failed boots in a row: greetd off, GDM on, counter reset, reboot asked for"
fi

# The revert must SAY what it did, in a greppable line.
if grep -q "SWITCHING BACK TO GDM" "${ROOT}/said.txt"; then
    pass "the revert says 'SWITCHING BACK TO GDM' where a person can find it"
else
    fail "the revert happened but said nothing greppable about it"
fi

# ==============================================================================
echo ""
echo "== the things that make it stand aside =="
# ==============================================================================

# ⚠️ THE STATE OF EVERY DEFAULT AQUARIUSOS MACHINE: GDM is the login screen, not
# greetd. The watchdog must do nothing at all — not watch, not touch the counter.
scenario gdm-is-the-login-screen
rm -f "${STUBS}/greetd-enabled"
set_counter 1
run_watchdog
if reverted; then
    fail "GDM is the login screen and it rebooted the machine anyway"
    sed 's/^/       /' "${ROOT}/said.txt"
elif [ "$(counter)" != "1" ]; then
    fail "it touched the counter on a GDM machine (it is $(counter), should be 1)"
elif grep -q "DID NOT CHANGE THE LOGIN SCREEN" "${ROOT}/said.txt"; then
    pass "GDM is in use: it stands aside and says so, touching nothing"
else
    fail "it stood aside without saying so — the journal cannot answer 'was it you?'"
    sed 's/^/       /' "${ROOT}/said.txt"
fi

# Already acted this boot: the /run stamp must stop a second action.
scenario already-acted
set_counter 1
: > "${ROOT}/run/aquarius/greeter-watchdog-acted"
run_watchdog
if reverted; then
    fail "it acted twice in one boot — the stamp under /run did not stop it"
else
    pass "it had already acted this boot: it did nothing"
fi

# ==============================================================================
echo ""
echo "== --status runs and --now reverts on demand =="
# ==============================================================================
scenario status
set_counter 1
if AQ_GREETER_WATCHDOG_ROOT="${ROOT}" AQ_STUB_DIR="${STUBS}" \
    PATH="${WORK}/bin:${PATH}" bash "${WD}" --status > "${ROOT}/status.txt" 2>&1; then
    if grep -q "greetd" "${ROOT}/status.txt"; then
        pass "--status runs and reports on the greeter"
    else
        fail "--status ran but said nothing useful"
    fi
else
    fail "--status exited non-zero"
    sed 's/^/       /' "${ROOT}/status.txt"
fi

scenario now
run_watchdog_now() {
    AQ_GREETER_WATCHDOG_ROOT="${ROOT}" AQ_STUB_DIR="${STUBS}" \
        PATH="${WORK}/bin:${PATH}" bash "${WD}" --now > "${ROOT}/now.txt" 2>&1
}
run_watchdog_now
if reverted && gdm_enabled; then
    pass "--now switches back to GDM immediately"
else
    fail "--now did not revert to GDM"
    sed 's/^/       /' "${ROOT}/now.txt"
fi

# ==============================================================================
echo ""
echo "== the rules that cannot be checked by running it =="
# ==============================================================================
if bash -n "${WD}"; then
    pass "the watchdog is valid shell"
else
    fail "the watchdog does not parse as shell"
fi

# The counter MUST live under /var/lib, not /run: it has to survive the reboot,
# because the whole point is to notice the SECOND bad boot.
if grep -q 'AQ_FAILS="${AQ_STATE_DIR}/greeter-fails"' "${WD}" \
    && grep -q 'AQ_STATE_DIR="${AQ_ROOT}/var/lib/aquarius"' "${WD}"; then
    pass "the failure counter is under /var/lib, so it survives a reboot"
else
    fail "the failure counter is not clearly under /var/lib — it would not survive a reboot"
fi

# The once-per-boot stamp MUST live under /run, so it resets every boot.
if grep -q '^AQ_STAMP_DIR="/run/' "${WD}"; then
    pass "its 'already acted' stamp is under /run, so it resets at each boot"
else
    fail "the watchdog's stamp is not under /run"
fi

echo ""
echo "  passed ${PASSED}, failed ${FAILED}"
if [ "${FAILED}" -ne 0 ]; then
    echo "  The net that is supposed to rescue a machine stuck behind the Aquarius"
    echo "  greeter would not rescue it. See docs/restart/login.md."
    exit 1
fi
echo "  The watchdog reverts to GDM after two failed greetd boots and only then."
exit 0
