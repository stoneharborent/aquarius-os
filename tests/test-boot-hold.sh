#!/usr/bin/bash
# =============================================================================
# test-boot-hold.sh — the login screen waits for the right amount of time
# =============================================================================
# WHAT THIS PROVES
#
# /usr/libexec/aquarius-boot-hold is what makes the login screen wait so that
# the boot animation can be seen. Until 2026-09-08 it was `sleep 3.5`, and the
# bench journal showed the flaw: the sleep began a whole second after the
# animation appeared, because the graphics driver and udev sat in between. It
# now asks systemd when plymouth-start.service really became active and waits
# only for what is left of the story.
#
# That is arithmetic on two clocks, and arithmetic in a shell script is exactly
# the kind of thing that is right in the author's head and wrong on the machine.
# So this runs the real program against a STAND-IN `systemctl` that answers
# whatever this test wants it to, and checks the sum it prints.
#
# The four cases:
#
#   1. The animation appeared a tenth of a second ago  → wait nearly the whole
#      4.3 seconds.
#   2. The animation appeared six seconds ago          → wait nothing at all.
#   3. systemd has no answer (a build container, or a machine with no boot
#      animation)                                     → fall back to the old
#      flat 3.5 seconds rather than skipping the hold.
#   4. Something absurd — the animation "appeared" an hour in the future →
#      never wait longer than the six-second ceiling.
#
# Case 3 is the one that matters most: a wrong answer there is a login screen
# that never waits, which is the fault this whole thing exists to fix, and it
# would look exactly like everything working.
#
# HOW TO RUN IT
#   ./tests/test-boot-hold.sh                                (the repo's copy)
#   ./tests/test-boot-hold.sh /usr/libexec/aquarius-boot-hold  (an image's copy)
#
# It needs nothing but bash, awk and a writable temporary folder. No systemd, no
# Plymouth, no screen — which is why it can run before the image is even built.
# =============================================================================

set -uo pipefail

HOLD="${1:-}"
if [ -z "${HOLD}" ]; then
    HOLD="$(cd "$(dirname "$0")/.." && pwd)/system_files/usr/libexec/aquarius-boot-hold"
fi

if [ ! -r "${HOLD}" ]; then
    echo "FAIL ${HOLD} is not there — nothing to test." >&2
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
# The stand-in systemctl
# -----------------------------------------------------------------------------
# It answers exactly one question — "when did plymouth-start.service become
# active?" — with whatever is in ${WORK}/answer. An empty file means "no answer",
# which is what a build container's systemctl really does.
mkdir -p "${WORK}/bin"
cat > "${WORK}/bin/systemctl" <<'STANDIN'
#!/usr/bin/bash
cat "${AQ_TEST_ANSWER}" 2>/dev/null || true
exit 0
STANDIN
chmod 0755 "${WORK}/bin/systemctl"
export AQ_TEST_ANSWER="${WORK}/answer"

# The program reads "now" from /proc/uptime, which this test cannot fake. So the
# answers below are worked out FROM the real /proc/uptime at the moment each
# case runs, which is the same thing from the program's point of view.
now_us() {
    awk -v u="$(cut -d' ' -f1 /proc/uptime)" 'BEGIN { printf "%d", u * 1000000 }'
}

# run_case "<name>" <seconds ago, or the word none> "<what the wait must be>"
run_case() {
    local name="$1" ago="$2" expected="$3" out line got
    if [ "${ago}" = "none" ]; then
        : > "${WORK}/answer"
    else
        awk -v n="$(now_us)" -v a="${ago}" \
            'BEGIN { printf "%d\n", n - (a * 1000000) }' > "${WORK}/answer"
    fi

    out="$(PATH="${WORK}/bin:${PATH}" "${HOLD}" --explain 2>&1)"

    # The program prints its sum in one of two shapes. Pull the number out of
    # whichever it printed.
    if line="$(printf '%s\n' "${out}" | grep -o 'waits [0-9.]*s more')"; then
        got="${line#waits }"
        got="${got%s more}"
    elif line="$(printf '%s\n' "${out}" | grep -o 'flat [0-9.]*s')"; then
        got="${line#flat }"
        got="${got%s}"
    else
        bad "${name}: could not find a wait in what it printed:"
        printf '%s\n' "${out}" | sed 's/^/         /' >&2
        return
    fi

    if awk -v g="${got}" -v e="${expected}" \
        'BEGIN { exit !(g >= e - 0.35 && g <= e + 0.35) }'; then
        ok "${name}: it would wait ${got}s (wanted about ${expected}s)"
    else
        bad "${name}: it would wait ${got}s, but ${expected}s was wanted"
        printf '%s\n' "${out}" | sed 's/^/         /' >&2
    fi
}

echo "== the hold's arithmetic, against a stand-in clock =="
echo "   program under test: ${HOLD}"

# 1. The animation has only just appeared: almost all of the story is still to
#    come, so almost all of the 4.3 seconds must be waited.
run_case "the animation appeared a moment ago" 0.1 4.2

# 2. The animation appeared six seconds ago: the story is long over and the
#    login screen must not be held back for a single second more.
run_case "the animation appeared six seconds ago" 6 0

# 3. ⚠️ THE IMPORTANT ONE. systemd cannot say. The old flat wait is the answer;
#    "no answer" must never mean "do not wait".
run_case "systemd has no answer at all" none 3.5

# 4. A nonsense answer from the future must not become a long wait.
awk -v n="$(now_us)" 'BEGIN { printf "%d\n", n + 3600000000 }' > "${WORK}/answer"
out="$(PATH="${WORK}/bin:${PATH}" "${HOLD}" --explain 2>&1)"
if printf '%s\n' "${out}" | grep -q 'waits 6.00s more'; then
    ok "an impossible answer is capped at the six-second ceiling"
else
    bad "an impossible answer was NOT capped at six seconds:"
    printf '%s\n' "${out}" | sed 's/^/         /' >&2
fi

# 5. It must always exit 0. A hold that fails would mark the boot as failed and
#    print a "Failed Units" line under the login banner for ever after.
: > "${WORK}/answer"
if PATH="${WORK}/bin:${PATH}" "${HOLD}" --explain > /dev/null 2>&1; then
    ok "it exits 0, so a boot is never marked failed because of the hold"
else
    bad "it exited non-zero — that would show up as a failed unit every boot"
fi

echo ""
if [ "${fails}" -ne 0 ]; then
    echo "::error::The boot hold's arithmetic is wrong (${fails} check(s) failed)."
    echo "The login screen would not wait for the boot animation. See"
    echo "docs/restart/boot-branding.md."
    exit 1
fi
echo "All boot-hold checks passed."
