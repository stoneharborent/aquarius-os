#!/usr/bin/env bash
# ==============================================================================
# Tests for "can the login screen actually draw what we hand it?"
# ==============================================================================
# THE BUG THESE TESTS EXIST FOR
#
# 2026-09-05, the bench: Royce turned the machine on and got a black screen with
# a mouse pointer on it and nothing else. No login screen, no error, no way in.
#
# Removing two files — /etc/xdg/monitors.xml and
# /var/lib/gdm/.config/monitors.xml — and restarting the login screen brought it
# straight back. Both files are copies of Royce's own display arrangement, made
# by /usr/libexec/aquarius-gdm-display so that the login screen would be the
# same size as his desktop. His says 125%.
#
# So AquariusOS now sanitises that copy before handing it over:
# /usr/libexec/aquarius-monitors-sanitize turns a part size into the nearest
# whole one, and refuses to produce anything at all out of a file it cannot
# understand. These tests are that program's rule table, executed.
#
# WHY A TEST AND NOT A BENCH CHECK
#
# The failure this guards against is not visible until a machine boots, and when
# it happens the machine cannot be logged into to investigate. The rule has to
# be right before it ships, which means it has to be checked somewhere that runs
# on every commit. Every fixture below is a real monitor arrangement, and the
# first one is Royce's.
#
# HOW TO RUN IT
#   ./tests/test-gdm-scale-sanitize.sh
#   ./tests/test-gdm-scale-sanitize.sh /usr/libexec/aquarius-monitors-sanitize \
#                                      /usr/libexec/aquarius-gdm-display
# ==============================================================================

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
SANITIZER="${1:-${HERE}/../system_files/usr/libexec/aquarius-monitors-sanitize}"
MESSENGER="${2:-${HERE}/../system_files/usr/libexec/aquarius-gdm-display}"

for f in "${SANITIZER}" "${MESSENGER}"; do
    if [ ! -r "${f}" ]; then
        echo "test-gdm-scale-sanitize: cannot read ${f}" >&2
        exit 1
    fi
done

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
# A monitors.xml, the shape GNOME really writes them
# ------------------------------------------------------------------------------
# Arguments: connector, scale, width, height. An empty scale writes no <scale>
# element at all, which is a real and separate case — it means 100%.
fixture() {
    local name="$1" connector="$2" scale="$3" width="$4" height="$5"
    local scale_line=""
    [ -n "${scale}" ] && scale_line="      <scale>${scale}</scale>"
    cat > "${WORK}/${name}.xml" << EOF
<monitors version="2">
  <configuration>
    <logicalmonitor>
      <x>0</x>
      <y>0</y>
${scale_line}
      <primary>yes</primary>
      <monitor>
        <monitorspec>
          <connector>${connector}</connector>
          <vendor>TST</vendor>
          <product>Test Monitor</product>
          <serial>0x00000001</serial>
        </monitorspec>
        <mode>
          <width>${width}</width>
          <height>${height}</height>
          <rate>59.997</rate>
        </mode>
      </monitor>
    </logicalmonitor>
  </configuration>
</monitors>
EOF
    echo "${WORK}/${name}.xml"
}

# What scale came out? Blank if the file has none, which is itself an answer.
scale_of() {
    sed -n 's:.*<scale>\(.*\)</scale>.*:\1:p' "$1" 2> /dev/null | tr -d ' '
}

# Run the sanitiser over a fixture and check the size it produced.
check_scale() {
    local label="$1" input="$2" expected="$3"
    shift 3
    local output="${WORK}/out-$$.xml"
    rm -f "${output}"

    if ! "${SANITIZER}" "$@" "${input}" "${output}" > "${WORK}/said.txt" 2>&1; then
        fail "${label}: the sanitiser refused the file (it should have accepted it)"
        sed 's/^/       /' "${WORK}/said.txt"
        return
    fi

    local got
    got="$(scale_of "${output}")"
    if [ "${got}" = "${expected}" ]; then
        pass "${label}: ${expected}"
    else
        fail "${label}: expected ${expected}, got '${got}'"
        sed 's/^/       /' "${WORK}/said.txt"
    fi
}

echo "== the size the login screen is given =="
# ⚠️ THE FIRST ONE IS THE BUG. Royce's 55-inch 4K screen at 125%, which is the
# exact file that produced a black screen on 2026-09-05. If this line ever goes
# red, that machine will not boot to a login screen.
check_scale "Royce's Ark: one 4K screen at 125% becomes 100%" \
    "$(fixture ark DP-1 1.25 3840 2160)" 1

check_scale "a laptop at 200% is left alone" \
    "$(fixture laptop eDP-1 2.0 2560 1600)" 2.0

check_scale "a whole size written without a decimal point is left alone" \
    "$(fixture plain eDP-1 2 2560 1600)" 2

check_scale "150% on a 4K screen rounds UP to 200% — there is room" \
    "$(fixture big DP-1 1.5 3840 2160)" 2

# The other half of the same rule, and the reason it is a rule and not just
# rounding: on a 1080p screen, 200% would leave 960x540 to draw a login screen
# on, which is below the floor. So it goes DOWN instead.
check_scale "150% on a 1080p screen rounds DOWN — 200% would leave too little" \
    "$(fixture small DP-2 1.5 1920 1080)" 1

check_scale "175% becomes 200%" \
    "$(fixture bigger DP-1 1.75 3840 2160)" 2

check_scale "a size of zero is nonsense and becomes 100%" \
    "$(fixture zero DP-1 0 3840 2160)" 1

check_scale "a size no screen could have becomes 100%" \
    "$(fixture huge DP-1 12 3840 2160)" 1

check_scale "a size that is not a number at all becomes 100%" \
    "$(fixture words DP-1 enormous 3840 2160)" 1

check_scale "a file that names no size is left alone (it means 100%)" \
    "$(fixture nosize DP-1 '' 3840 2160)" ""

echo ""
echo "== part sizes, when somebody has switched them on =="
check_scale "with --allow-fractional, 125% is passed straight through" \
    "$(fixture arkf DP-1 1.25 3840 2160)" 1.25 --allow-fractional

echo ""
echo "== a file we do not understand is never handed over =="
# ⚠️ THIS IS THE ONE THAT MATTERS MOST AFTER THE FIRST. The contract is that a
# non-zero exit means "nothing was written, do not copy anything" — and the
# messenger relies on it. If a broken file ever produced a zero exit and no
# output, the messenger would copy a file that is not there; if it produced a
# zero exit and a HALF-WRITTEN output, it would copy that. Both are the black
# screen again, by a different road.
broken_check() {
    local label="$1" input="$2"
    local output="${WORK}/out-broken.xml"
    rm -f "${output}"
    "${SANITIZER}" "${input}" "${output}" > "${WORK}/said.txt" 2>&1
    local rc=$?

    if [ "${rc}" -eq 0 ]; then
        fail "${label}: the sanitiser said it was fine (it must refuse)"
        return
    fi
    if [ -e "${output}" ]; then
        fail "${label}: it refused, but wrote ${output} anyway"
        return
    fi
    if [ ! -s "${WORK}/said.txt" ]; then
        fail "${label}: it refused in silence — nothing would explain the login screen's size"
        return
    fi
    pass "${label}: refused, wrote nothing, and said why"
    sed 's/^/       said: /' "${WORK}/said.txt"
}

printf '<monitors><configuration><logicalmonitor>' > "${WORK}/truncated.xml"
broken_check "a half-written file" "${WORK}/truncated.xml"

printf 'this is not xml at all\n' > "${WORK}/notxml.xml"
broken_check "a file that is not XML" "${WORK}/notxml.xml"

printf '<something><else/></something>\n' > "${WORK}/wrongdoc.xml"
broken_check "valid XML that is not a display arrangement" "${WORK}/wrongdoc.xml"

printf '<monitors version="2"/>\n' > "${WORK}/empty.xml"
broken_check "a display arrangement with nothing in it" "${WORK}/empty.xml"

broken_check "a file that is not there at all" "${WORK}/no-such-file.xml"

echo ""
echo "== the messenger really uses the sanitiser =="
# ------------------------------------------------------------------------------
# End to end, against the real messenger, with fake home folders.
# ------------------------------------------------------------------------------
# This is the test that would have caught the original bug, because the original
# bug was not a wrong rule — it was a copy with no rule in front of it. Checking
# the sanitiser alone proves the rule exists; only this proves it is USED.
#
# AQ_GDM_DISPLAY_ROOT moves every path the messenger writes to underneath a
# temporary folder, so this runs as an ordinary user and touches nothing.
run_messenger() {
    local root="$1"
    shift
    AQ_GDM_DISPLAY_ROOT="${root}" \
        AQ_SANITIZER_OVERRIDE="${SANITIZER}" \
        AQ_SCALE_HELPER_OVERRIDE="${root}/no-such-helper" \
        bash "${MESSENGER}" "$@" > "${root}/said.txt" 2>&1
}

ROOT="${WORK}/root"
mkdir -p "${ROOT}/home/royce/.config"
cp "$(fixture arkend DP-1 1.25 3840 2160)" "${ROOT}/home/royce/.config/monitors.xml"

if run_messenger "${ROOT}"; then
    pass "the messenger ran and finished cleanly"
else
    fail "the messenger failed"
    sed 's/^/       /' "${ROOT}/said.txt"
fi

for target in "${ROOT}/etc/xdg/monitors.xml" "${ROOT}/var/lib/gdm/.config/monitors.xml"; do
    short="${target#"${ROOT}"}"
    if [ ! -r "${target}" ]; then
        fail "${short} was never written"
        continue
    fi
    got="$(scale_of "${target}")"
    if [ "${got}" = "1" ]; then
        pass "${short} was given 100%, not 125%"
    else
        fail "${short} was given '${got}' — the login screen could go black"
    fi
done

# The one number our OWN login screen reads is a different question with a
# different answer, and conflating the two would quietly make the Aquarius
# greeter small on every 4K machine. labwc does part sizes properly.
if grep -q "1.25" "${ROOT}/home/royce/.config/monitors.xml"; then
    pass "the person's own file was not modified"
else
    fail "the messenger changed the user's own monitors.xml — it must never do that"
fi

if [ -s "${ROOT}/var/lib/aquarius/gdm-display.log" ]; then
    pass "it wrote down what it did (gdm-display.log)"
    if grep -q "125%" "${ROOT}/var/lib/aquarius/gdm-display.log"; then
        pass "and the log names the size it changed"
    else
        fail "the log does not say which size was changed — it is the only explanation a person gets"
    fi
else
    fail "nothing was written to the log — a person could not find out why their login screen shrank"
fi

echo ""
echo "== switching part sizes on changes the answer =="
ROOT2="${WORK}/root2"
mkdir -p "${ROOT2}/home/royce/.config" "${ROOT2}/var/lib/aquarius"
cp "$(fixture arkend2 DP-1 1.25 3840 2160)" "${ROOT2}/home/royce/.config/monitors.xml"
: > "${ROOT2}/var/lib/aquarius/gdm-fractional-ok"

run_messenger "${ROOT2}"
got="$(scale_of "${ROOT2}/etc/xdg/monitors.xml")"
if [ "${got}" = "1.25" ]; then
    pass "with the marker file present, 125% reaches the login screen"
else
    fail "the marker file did nothing — expected 1.25, got '${got}'"
    sed 's/^/       /' "${ROOT2}/said.txt"
fi

echo ""
echo "== the messenger refuses rather than copying something it cannot check =="
# If the sanitiser is missing the messenger must copy NOTHING. The tempting
# behaviour — "fall back to copying the original" — is precisely the bug.
ROOT3="${WORK}/root3"
mkdir -p "${ROOT3}/home/royce/.config"
cp "$(fixture arkend3 DP-1 1.25 3840 2160)" "${ROOT3}/home/royce/.config/monitors.xml"

AQ_GDM_DISPLAY_ROOT="${ROOT3}" \
    AQ_SANITIZER_OVERRIDE="${ROOT3}/no-such-sanitizer" \
    AQ_SCALE_HELPER_OVERRIDE="${ROOT3}/no-such-helper" \
    bash "${MESSENGER}" > "${ROOT3}/said.txt" 2>&1
rc=$?

if [ "${rc}" -ne 0 ]; then
    fail "with no sanitiser the messenger failed (it must exit cleanly, not fail)"
elif [ -e "${ROOT3}/etc/xdg/monitors.xml" ]; then
    fail "with no sanitiser it copied the file anyway — that is the original bug"
else
    pass "with no sanitiser it copied nothing and exited cleanly"
fi

echo ""
echo "== the guard cannot loop =="
GUARD="${HERE}/../system_files/usr/libexec/aquarius-gdm-guard"
if [ -r "${GUARD}" ]; then
    if bash -n "${GUARD}"; then
        pass "the guard is valid shell"
    else
        fail "the guard does not parse as shell"
    fi
    # The stamp is the thing that makes a repair happen at most once per boot.
    # It has to live under /run, which is emptied at every boot — a stamp under
    # /var would mean the guard repairs once and then never again, for the life
    # of the machine.
    if grep -q '^AQ_STAMP_DIR="/run/' "${GUARD}"; then
        pass "its 'already tried' stamp is under /run, so it resets at each boot"
    else
        fail "the guard's stamp is not under /run — it would only ever repair once, ever"
    fi
    if grep -q 'is-enabled gdm.service' "${GUARD}"; then
        pass "it stands aside when GDM is not the login screen in use"
    else
        fail "the guard does not check that GDM is in use — it could restart greetd"
    fi
else
    fail "${GUARD} is missing"
fi

echo ""
echo "  passed ${PASSED}, failed ${FAILED}"
if [ "${FAILED}" -ne 0 ]; then
    echo "  The login screen could be handed a size it cannot draw — the black"
    echo "  screen of 2026-09-05, back again. See docs/restart/login.md."
    exit 1
fi
echo "  The login screen is only ever handed a size it can draw."
exit 0
