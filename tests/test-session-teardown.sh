#!/usr/bin/env bash
# ==============================================================================
# Tests for "does logging out actually leave the machine clean?"
# ==============================================================================
# THE BUG THESE TESTS EXIST FOR
#
# 2026-09-04, the bench: logging out of the Aquarius Desktop to go to GNOME
# bounced off the login screen two or three times before GNOME would start. The
# cause was that the Aquarius session left its settings on the user's systemd
# noticeboard and left its background programs running, and GNOME then tripped
# over both. The fix is /usr/libexec/aquarius-session-lib.
#
# HOW YOU TEST A LOGOUT WITHOUT LOGGING OUT
#
# You cannot run the real thing here: a container build has no desktop, no
# session, and no systemd user manager. So the four commands the clean-up talks
# to the outside world with — systemctl, pkill, dbus-update-activation-
# environment and id — are replaced with little stand-ins that write down what
# they were asked to do and answer plausibly. The clean-up runs for real
# against those, and the tests then read the transcript.
#
# That is a genuinely useful thing to check, because the bugs this code can have
# are bugs of ORDER and of COMPLETENESS, and both are visible in a transcript:
#
#   * unsetting the settings BEFORE stopping the services would let a service
#     that is still shutting down write them back,
#   * killing programs before asking them to stop is rude and loses work,
#   * and a variable the launcher sets but the clean-up forgets is the original
#     bug, exactly, returning.
#
# The last one is the important one and it is checked against the REAL launcher
# rather than against a list: every `export` in /usr/bin/aquarius-session has to
# appear in the library's list, or this fails.
#
# HOW TO RUN IT
#   ./tests/test-session-teardown.sh
#   ./tests/test-session-teardown.sh /usr/libexec/aquarius-session-lib /usr/bin/aquarius-session
# ==============================================================================

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="${1:-${HERE}/../system_files/usr/libexec/aquarius-session-lib}"
LAUNCHER="${2:-${HERE}/../system_files/usr/bin/aquarius-session}"

for f in "$LIB" "$LAUNCHER"; do
    if [ ! -r "$f" ]; then
        echo "test-session-teardown: cannot read ${f}" >&2
        exit 1
    fi
done

export LC_ALL=C

PASSED=0
FAILED=0

pass() { echo "  ok   $*"; PASSED=$((PASSED + 1)); }
fail() { echo "  FAIL $*"; FAILED=$((FAILED + 1)); }

# check "<what>" "<result>"
#
# <result> is 0 for "this is fine" and anything else for "this is not". It may
# also carry a few lines of detail ABOVE the number — several of the checks
# below want to print exactly which name was wrong before they say so — so only
# the LAST line is read as the verdict and everything before it is shown.
check() {
    local aq_verdict aq_detail
    aq_verdict="$(printf '%s' "$2" | tail -n 1)"
    aq_detail="$(printf '%s' "$2" | sed '$d')"
    if [ "${aq_verdict}" = "0" ]; then
        pass "$1"
    else
        fail "$1"
        [ -n "${aq_detail}" ] && printf '%s\n' "${aq_detail}"
    fi
    return 0
}

# shellcheck source=../system_files/usr/libexec/aquarius-session-lib
. "$LIB"

# ------------------------------------------------------------------------------
# The pretend outside world.
#
# Every stand-in appends one line to $TRANSCRIPT and then answers the way the
# real thing would. They are written into a temporary folder which is put at the
# front of PATH, so the library finds them without knowing anything about this.
# ------------------------------------------------------------------------------
STUBS="$(mktemp -d)"
TRANSCRIPT="${STUBS}/transcript"
trap 'rm -rf "${STUBS}"' EXIT

: > "${TRANSCRIPT}"

# systemctl. `is-active` answers from a file the tests can change, which is how
# the "a service refuses to stop" case is set up.
cat > "${STUBS}/systemctl" <<'STUB'
#!/usr/bin/env bash
echo "systemctl $*" >> "${TRANSCRIPT}"
for arg in "$@"; do
    if [ "${arg}" = "is-active" ]; then
        [ -f "${STUBS_STILL_ACTIVE}" ] && exit 0
        exit 3
    fi
done
exit 0
STUB

# pkill. Answers "yes, I found something" for the names listed in
# $STUBS_ALIVE_NAMES and "no such process" (exit 1) for everything else, which
# is what the real pkill does.
cat > "${STUBS}/pkill" <<'STUB'
#!/usr/bin/env bash
echo "pkill $*" >> "${TRANSCRIPT}"
name="${!#}"
case " ${STUBS_ALIVE_NAMES:-} " in
    *" ${name} "*) exit 0 ;;
    *) exit 1 ;;
esac
STUB

cat > "${STUBS}/dbus-update-activation-environment" <<'STUB'
#!/usr/bin/env bash
echo "dbus-update-activation-environment $*" >> "${TRANSCRIPT}"
exit 0
STUB

cat > "${STUBS}/id" <<'STUB'
#!/usr/bin/env bash
echo 1000
STUB

# sleep is stubbed to do nothing. Without this the whole suite would take the
# real clean-up's timeouts to run — which on the "nothing stops" case is ten
# seconds of a build machine sitting still, every build, forever.
cat > "${STUBS}/sleep" <<'STUB'
#!/usr/bin/env bash
echo "sleep $*" >> "${TRANSCRIPT}"
exit 0
STUB

chmod 0755 "${STUBS}"/*
export PATH="${STUBS}:${PATH}"
export TRANSCRIPT
export STUBS_STILL_ACTIVE="${STUBS}/still-active"
export STUBS_ALIVE_NAMES=""

# `timeout` runs its argument in a way that would bypass our PATH stubs on some
# systems; the library uses it, so make sure the stub folder is exported to the
# child too. (PATH already is, above — this is just the note that it matters.)

# Where in the transcript did a thing happen? Prints a line number, or nothing.
line_of() { grep -n -- "$1" "${TRANSCRIPT}" | head -1 | cut -d: -f1; }

# ==============================================================================
echo "== the lists agree with each other =="
# ==============================================================================
UNSET_LIST="$(aq_session_env_unset_list)"
echo "  push:  ${AQ_SESSION_ENV_PUSH}"
echo "  extra: ${AQ_SESSION_ENV_COMPOSITOR}"
echo "  keep:  ${AQ_SESSION_ENV_KEEP}"
echo "  unset: ${UNSET_LIST}"

# Everything set and not deliberately kept must be removed.
missing=""
for name in ${AQ_SESSION_ENV_PUSH} ${AQ_SESSION_ENV_COMPOSITOR}; do
    kept=0
    for keep in ${AQ_SESSION_ENV_KEEP}; do
        [ "${name}" = "${keep}" ] && kept=1
    done
    [ "${kept}" -eq 1 ] && continue
    case " ${UNSET_LIST} " in
        *" ${name} "*) ;;
        *) missing="${missing} ${name}" ;;
    esac
done
check "every setting this session makes is also removed again" \
    "$([ -z "${missing}" ] && echo 0 || { echo "        not removed:${missing}"; echo 1; })"

# And nothing we said to keep is removed.
wrongly_removed=""
for keep in ${AQ_SESSION_ENV_KEEP}; do
    case " ${UNSET_LIST} " in
        *" ${keep} "*) wrongly_removed="${wrongly_removed} ${keep}" ;;
    esac
done
check "LANG is kept, because it is the person's language and not this desktop's" \
    "$([ -z "${wrongly_removed}" ] && echo 0 || echo 1)"

# ⚠️ And LANG is the ONLY thing kept. This looks pedantic and is not: the
# keep-list is the one place where a settings leak can be introduced by adding
# a single word, with the check above still passing. Adding to it is a decision
# that has to be argued for in the library's comments and here, together.
check "and LANG is the only thing kept — anything else added here is a settings leak" \
    "$([ "${AQ_SESSION_ENV_KEEP}" = "LANG" ] && echo 0 || { echo "        the keep-list is now: ${AQ_SESSION_ENV_KEEP}"; echo 1; })"

# The two the window manager adds are the ones that must never survive.
for must in WAYLAND_DISPLAY DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE; do
    case " ${UNSET_LIST} " in
        *" ${must} "*) pass "${must} is removed at logout" ;;
        *) fail "${must} is NOT removed — this is the bug of 2026-09-04 exactly" ;;
    esac
done

# ==============================================================================
echo "== the launcher and the list cannot drift apart =="
# ==============================================================================
# THE POINT OF THIS TEST. Read the real launcher, find every variable it
# exports, and require each one to be in the library's list. A new export with
# no matching entry is a settings leak into the next login, and it fails here
# rather than on somebody's bench in three months.
EXPORTED="$(grep -oE '^[[:space:]]*export [A-Z_][A-Z0-9_]*' "${LAUNCHER}" \
            | awk '{print $2}' | sort -u)"
echo "  the launcher exports: $(echo "${EXPORTED}" | tr '\n' ' ')"

if [ -z "${EXPORTED}" ]; then
    fail "no exports found in ${LAUNCHER} — the test is reading the wrong file"
else
    unlisted=""
    for name in ${EXPORTED}; do
        case " ${AQ_SESSION_ENV_PUSH} " in
            *" ${name} "*) ;;
            *) unlisted="${unlisted} ${name}" ;;
        esac
    done
    if [ -z "${unlisted}" ]; then
        pass "every variable the launcher exports is in AQ_SESSION_ENV_PUSH"
    else
        fail "the launcher exports${unlisted} but the library does not list them — they would be left behind at logout. Add them to AQ_SESSION_ENV_PUSH in the library."
    fi
fi

# The reverse: the launcher must actually USE the library's list rather than
# repeating it, or the check above proves nothing.
if grep -q 'aq_push_env \${\?AQ_SESSION_ENV_PUSH' "${LAUNCHER}"; then
    pass "the launcher hands systemd the library's list, not a copy of it"
else
    fail "the launcher does not use AQ_SESSION_ENV_PUSH — the two lists can drift"
fi

# And it must arm the clean-up on every way out, not just the tidy one.
if grep -q "^trap 'aq_session_teardown' EXIT" "${LAUNCHER}"; then
    pass "the clean-up is armed with a trap, so it runs even if the session crashes"
else
    fail "the launcher does not trap EXIT — a crash would skip the clean-up entirely"
fi
if grep -qE '^exec labwc' "${LAUNCHER}"; then
    fail "the launcher still uses 'exec labwc' — nothing would be left alive to clean up afterwards"
else
    pass "the launcher runs the window manager as a child, so it outlives it and can clean up"
fi

# ==============================================================================
echo "== a normal logout, with everything behaving =="
# ==============================================================================
: > "${TRANSCRIPT}"
rm -f "${STUBS_STILL_ACTIVE}"
export STUBS_ALIVE_NAMES="qs swaybg"

aq_session_teardown > "${STUBS}/say.log" 2>&1

echo "  --- what the clean-up did ---"
sed 's/^/      /' "${TRANSCRIPT}"

STOP_AT="$(line_of 'systemctl --user stop')"
UNSET_AT="$(line_of 'unset-environment')"
KILL_AT="$(line_of 'pkill')"
RESET_AT="$(line_of 'reset-failed')"

check "the services are stopped"            "$([ -n "${STOP_AT}" ] && echo 0 || echo 1)"
check "the settings are removed"            "$([ -n "${UNSET_AT}" ] && echo 0 || echo 1)"
check "leftover programs are closed"        "$([ -n "${KILL_AT}" ] && echo 0 || echo 1)"
check "the failure marks are cleared"       "$([ -n "${RESET_AT}" ] && echo 0 || echo 1)"

check "stop comes before removing the settings (a service still stopping could write them back)" \
    "$([ "${STOP_AT:-0}" -lt "${UNSET_AT:-0}" ] && echo 0 || echo 1)"
check "the settings are removed before anything is killed" \
    "$([ "${UNSET_AT:-0}" -lt "${KILL_AT:-0}" ] && echo 0 || echo 1)"
check "clearing the failure marks is last" \
    "$([ "${KILL_AT:-0}" -lt "${RESET_AT:-0}" ] && echo 0 || echo 1)"

# The two targets `man systemd.special` names have to be in the stop.
for unit in graphical-session.target labwc-session.target; do
    if grep -q -- "systemctl --user stop .*${unit}" "${TRANSCRIPT}"; then
        pass "${unit} is stopped"
    else
        fail "${unit} is not stopped — services that belong to the session would survive"
    fi
done

# The portals, so GNOME's own start fresh and read GNOME's configuration.
for unit in xdg-desktop-portal.service xdg-desktop-portal-wlr.service xdg-desktop-portal-gtk.service; do
    if grep -q -- "systemctl --user stop .*${unit}" "${TRANSCRIPT}"; then
        pass "${unit} is stopped, so the next desktop gets its own"
    else
        fail "${unit} is left running — it would answer GNOME with the Aquarius back end"
    fi
done

# Every name in the unset list has to actually be passed to systemd.
UNSET_LINE="$(grep 'unset-environment' "${TRANSCRIPT}" | head -1)"
absent=""
for name in ${UNSET_LIST}; do
    case " ${UNSET_LINE} " in
        *" ${name} "*) ;;
        *) absent="${absent} ${name}" ;;
    esac
done
check "every name on the list is really handed to systemd to forget" \
    "$([ -z "${absent}" ] && echo 0 || { echo "        never passed:${absent}"; echo 1; })"

# LANG must not be in that command.
case " ${UNSET_LINE} " in
    *" LANG "*) fail "LANG was unset — the next login would fall back to the 7-bit C locale" ;;
    *) pass "LANG was not unset" ;;
esac

# The D-Bus pass must NOT carry --systemd (see the warning in the library).
if grep 'dbus-update-activation-environment' "${TRANSCRIPT}" | grep -q -- '--systemd'; then
    fail "the D-Bus pass used --systemd, which would write empty values into systemd instead of removing them"
else
    pass "the D-Bus pass leaves systemd alone, so the real removal is not undone"
fi

# ==============================================================================
echo "== the killing is careful =="
# ==============================================================================
BAD_KILL=0
while read -r line; do
    case "${line}" in
        pkill*) ;;
        *) continue ;;
    esac
    case "${line}" in
        *--uid*) ;;
        *) echo "        not limited to this person: ${line}"; BAD_KILL=1 ;;
    esac
    case "${line}" in
        *--exact*) ;;
        *) echo "        not an exact name match: ${line}"; BAD_KILL=1 ;;
    esac
    name="${line##* }"
    case " ${AQ_SESSION_STRAGGLERS} " in
        *" ${name} "*) ;;
        *) echo "        killed something not on the list: ${name}"; BAD_KILL=1 ;;
    esac
done < "${TRANSCRIPT}"
check "every kill is this person's own, an exact name, and on the list" "${BAD_KILL}"

# Asked politely first, forced second, and only for what was actually running.
if grep -q 'pkill .*--signal TERM .*qs' "${TRANSCRIPT}"; then
    pass "the bar was asked to close before being forced"
else
    fail "the bar was not asked politely first"
fi
TERM_AT="$(line_of 'signal TERM')"
KILL9_AT="$(line_of 'signal KILL')"
check "the polite request comes before the forced one" \
    "$([ -n "${KILL9_AT}" ] && [ "${TERM_AT:-0}" -lt "${KILL9_AT}" ] && echo 0 || echo 1)"

if grep -q 'pkill .*--signal KILL .*slurp' "${TRANSCRIPT}"; then
    fail "something that was not running was still force-killed"
else
    pass "only the programs that were actually running were forced"
fi

# The bar is the one that must never survive: it holds the name every
# notification on the machine is delivered to, and GNOME's shell wants it.
case " ${AQ_SESSION_STRAGGLERS} " in
    *" qs "*) pass "the Aquarius bar is on the list of things to close" ;;
    *) fail "the bar is not closed — GNOME would start with no notifications" ;;
esac

# ==============================================================================
echo "== when something refuses to stop, the logout still finishes =="
# ==============================================================================
# The failure mode being prevented: one stuck service turning a logout into a
# ninety-second black screen. The clean-up gives up after its own time limit and
# reaches for the blunter tools instead.
: > "${TRANSCRIPT}"
touch "${STUBS_STILL_ACTIVE}"
export STUBS_ALIVE_NAMES="qs"
export AQ_SESSION_STOP_TIMEOUT=3

aq_session_teardown > "${STUBS}/say2.log" 2>&1
STATUS=$?

check "the clean-up finished anyway" "${STATUS}"
check "it said so in the log" \
    "$(grep -q 'did not stop within' "${STUBS}/say2.log" && echo 0 || echo 1)"
check "it gave up after the time limit rather than waiting forever" \
    "$([ "$(grep -c '^sleep 1$' "${TRANSCRIPT}")" -le 3 ] && echo 0 || echo 1)"
check "it still removed the settings" \
    "$(grep -q 'unset-environment' "${TRANSCRIPT}" && echo 0 || echo 1)"
check "it still closed the leftover programs" \
    "$(grep -q 'pkill' "${TRANSCRIPT}" && echo 0 || echo 1)"

export AQ_SESSION_STOP_TIMEOUT=10
rm -f "${STUBS_STILL_ACTIVE}"

# ==============================================================================
echo "== starting up: we protect ourselves from the LAST desktop too =="
# ==============================================================================
# An Aquarius session that is force-killed never runs its clean-up, and a GNOME
# session never cleans up on the way out at all. So arriving is defended as well
# as leaving — exactly the way GNOME defends itself (gsm-util.c unsets DISPLAY,
# WAYLAND_DISPLAY, XAUTHORITY and WAYLAND_SOCKET at login).
: > "${TRANSCRIPT}"
aq_session_env_reset > /dev/null 2>&1
RESET_LINE="$(grep 'unset-environment' "${TRANSCRIPT}" | head -1)"
echo "  ${RESET_LINE:-(nothing)}"
for v in ${AQ_SESSION_ENV_COMPOSITOR}; do
    case " ${RESET_LINE} " in
        *" ${v} "*) pass "logging in throws away the last desktop's ${v}" ;;
        *) fail "${v} is not cleared at login — a force-killed previous session would poison this one" ;;
    esac
done
check "the launcher really does that before naming its own screen" \
    "$(grep -q '^aq_session_env_reset$' "${LAUNCHER}" && echo 0 || echo 1)"

# ==============================================================================
echo "== starting up: the portals are made ours =="
# ==============================================================================
: > "${TRANSCRIPT}"
aq_session_portals_refresh > /dev/null 2>&1
check "logging IN stops the last desktop's portals too" \
    "$(grep -q 'systemctl --user stop .*xdg-desktop-portal' "${TRANSCRIPT}" && echo 0 || echo 1)"

# ⚠️ AND NOTHING ELSE. This runs at the START of a session, from the window
# manager's autostart file. If it ever reached graphical-session.target it would
# stop the session it is standing in — the desktop would tear itself down four
# seconds after login. That is the one way this helper could be catastrophic,
# so it is the one thing tested hardest.
OVERREACH=""
for unit in graphical-session.target labwc-session.target aquarius-keys.service; do
    if grep -q -- "${unit}" "${TRANSCRIPT}"; then
        OVERREACH="${OVERREACH} ${unit}"
    fi
done
check "and it touches nothing else — it must never stop the session it is starting" \
    "$([ -z "${OVERREACH}" ] && echo 0 || { echo "        it also stopped:${OVERREACH}"; echo 1; })"

# ==============================================================================
echo ""
echo "  passed ${PASSED}, failed ${FAILED}"
if [ "${FAILED}" -ne 0 ]; then
    echo "  The logout clean-up is wrong. Logging out of Aquarius into GNOME would"
    echo "  bounce off the login screen — the bug of 2026-09-04, back again."
    exit 1
fi
echo "  Logging out leaves the machine clean."
exit 0
