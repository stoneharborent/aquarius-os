#!/usr/bin/env bash
# ==============================================================================
# Tests for the guard that rescues a login screen that never appeared
# ==============================================================================
# THE BUG THESE TESTS EXIST FOR
#
# 2026-09-05. The bench booted to a black screen with a mouse pointer, for the
# SECOND time in two days — and this time the machine was running the image that
# had just added aquarius-gdm-guard, whose entire job is to notice exactly that
# and fix it by itself. It noticed nothing. Royce fixed it by hand again.
#
# The guard was enabled. It ran. It was not broken in any way a build log would
# show. It asked the wrong question:
#
#     "is there a graphical session on this machine?"
#
# and in a black-screen boot the answer is YES. The mouse pointer is drawn by
# the compositor — a pointer on the screen is proof that the greeter started and
# has a session. What was wrong was one step further in: the compositor came up
# and drew nothing, and logind cannot see that.
#
# So the guard was told "the login screen is up", twenty seconds into the boot,
# and exited reporting success while a person sat in front of a black screen.
#
# A safety net whose trigger has never been executed is not a safety net; it is
# a comment. These tests execute it, on both sides, with fake system commands.
#
# ------------------------------------------------------------------------------
# HOW THE FAKING WORKS
# ------------------------------------------------------------------------------
# The guard talks to the machine through four commands, and each is replaced
# here with a small script on PATH that answers from files in a temporary
# folder:
#
#   loginctl     which sessions exist (and it can answer DIFFERENTLY on each
#                call, which is the whole point of case 3)
#   systemctl    is GDM in use, how many times has it restarted, and it records
#                any restart the guard asks for instead of doing one
#   journalctl   what the compositor said
#   sleep        returns instantly, so 45 seconds of watching takes no time
#
# Everything else — the file removals, the decision, the log — is the real
# program. AQ_GDM_GUARD_ROOT puts every path it touches inside the temporary
# folder, so this runs as an ordinary user and changes nothing.
#
# HOW TO RUN IT
#   ./tests/test-gdm-guard.sh
#   ./tests/test-gdm-guard.sh /usr/libexec/aquarius-gdm-guard    (the installed one)
# ==============================================================================

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
GUARD="${1:-${HERE}/../system_files/usr/libexec/aquarius-gdm-guard}"

if [ ! -r "${GUARD}" ]; then
    echo "test-gdm-guard: cannot read ${GUARD}" >&2
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
# Written once, into ${WORK}/bin, and put at the front of PATH for every case.
# They read ${AQ_STUB_DIR}, which each case sets to its own folder.
make_stubs() {
    mkdir -p "${WORK}/bin"

    # loginctl. `list-sessions` pops the NEXT line of the sessions file each
    # time it is called, so a case can say "one session, then the same one, then
    # a different one" — which is what a login screen crashing and restarting
    # looks like from outside. When the lines run out the last one repeats.
    cat > "${WORK}/bin/loginctl" << 'STUB'
#!/usr/bin/env bash
d="${AQ_STUB_DIR}"
case "$1" in
  list-sessions)
    n=0
    [ -r "${d}/loginctl-calls" ] && n="$(cat "${d}/loginctl-calls")"
    n=$((n + 1))
    echo "${n}" > "${d}/loginctl-calls"
    [ -r "${d}/sessions" ] || exit 0
    total="$(wc -l < "${d}/sessions" | tr -d ' ')"
    [ "${n}" -gt "${total}" ] && n="${total}"
    [ "${total}" -eq 0 ] && exit 0
    line="$(sed -n "${n}p" "${d}/sessions")"
    for s in ${line}; do echo "${s} 1000 royce seat0 tty2"; done
    ;;
  show-session)
    # $2 is the session id. Everything named in the sessions file is a Wayland
    # session unless the case says otherwise.
    if [ -r "${d}/session-type" ]; then cat "${d}/session-type"; else echo wayland; fi
    ;;
  show-user)
    if [ -r "${d}/gdm-user-state" ]; then cat "${d}/gdm-user-state"; else echo ""; fi
    ;;
esac
exit 0
STUB

    # systemctl. Answers "is GDM in use", hands out a restart count that can
    # change between calls the same way, and WRITES DOWN any restart instead of
    # performing one.
    cat > "${WORK}/bin/systemctl" << 'STUB'
#!/usr/bin/env bash
d="${AQ_STUB_DIR}"
case "${1:-}" in
  is-enabled)
    [ -e "${d}/gdm-not-enabled" ] && exit 1
    echo enabled; exit 0
    ;;
  show)
    n=0
    [ -r "${d}/nrestarts-calls" ] && n="$(cat "${d}/nrestarts-calls")"
    n=$((n + 1))
    echo "${n}" > "${d}/nrestarts-calls"
    if [ -r "${d}/nrestarts" ]; then
      total="$(wc -l < "${d}/nrestarts" | tr -d ' ')"
      [ "${n}" -gt "${total}" ] && n="${total}"
      sed -n "${n}p" "${d}/nrestarts"
    else
      echo 0
    fi
    exit 0
    ;;
  restart)
    echo "$*" >> "${d}/restarted"
    exit 0
    ;;
esac
exit 0
STUB

    # journalctl. Whatever the case decided the compositor said.
    cat > "${WORK}/bin/journalctl" << 'STUB'
#!/usr/bin/env bash
[ -r "${AQ_STUB_DIR}/journal" ] && cat "${AQ_STUB_DIR}/journal"
exit 0
STUB

    # sleep. The guard watches for 45 seconds; a test must not.
    printf '#!/usr/bin/env bash\nexit 0\n' > "${WORK}/bin/sleep"

    chmod 0755 "${WORK}/bin/"*
}

# ------------------------------------------------------------------------------
# scenario <name>  — build a machine for the guard to look at
# ------------------------------------------------------------------------------
# Every scenario starts the same way: GDM is the login screen, both copied
# display files exist, nothing has happened yet. A case then changes one thing,
# which is what makes it readable: the difference IS the test.
make_stubs

ROOT=""
STUBS=""
scenario() {
    ROOT="${WORK}/$1/root"
    STUBS="${WORK}/$1/stubs"
    mkdir -p "${ROOT}/etc/xdg" "${ROOT}/var/lib/gdm/.config" \
        "${ROOT}/var/lib/aquarius" "${ROOT}/run/aquarius" "${STUBS}"
    echo '<monitors version="2"><configuration/></monitors>' \
        > "${ROOT}/etc/xdg/monitors.xml"
    echo '<monitors version="2"><configuration/></monitors>' \
        > "${ROOT}/var/lib/gdm/.config/monitors.xml"
}

run_guard() {
    AQ_GDM_GUARD_ROOT="${ROOT}" \
        AQ_GDM_GUARD_FIRST_LOOK=0 \
        AQ_GDM_GUARD_POLL_EVERY=1 \
        AQ_GDM_GUARD_TOTAL_WAIT=2 \
        AQ_STUB_DIR="${STUBS}" \
        PATH="${WORK}/bin:${PATH}" \
        bash "${GUARD}" > "${ROOT}/said.txt" 2>&1
}

acted() { [ -e "${STUBS}/restarted" ]; }
copies_gone() {
    [ ! -e "${ROOT}/etc/xdg/monitors.xml" ] \
        && [ ! -e "${ROOT}/var/lib/gdm/.config/monitors.xml" ]
}

# ==============================================================================
echo "== when the login screen really did come up, it must leave it alone =="
# ==============================================================================
# The guard restarting a healthy login screen would throw somebody out of a
# session they were half way through logging into. This is the case that has to
# be right first.
scenario healthy
printf 'c1\nc1\nc1\nc1\n' > "${STUBS}/sessions"
run_guard
rc=$?

if [ "${rc}" -ne 0 ]; then
    fail "the guard failed on a healthy machine (it must always exit cleanly)"
    sed 's/^/       /' "${ROOT}/said.txt"
elif acted; then
    fail "it restarted the login screen on a healthy machine"
    sed 's/^/       /' "${ROOT}/said.txt"
elif copies_gone; then
    fail "it deleted the display files on a healthy machine"
else
    pass "one steady session, no complaints: it did nothing"
fi

# ==============================================================================
echo ""
echo "== when nothing came up at all, it must repair =="
# ==============================================================================
scenario nothing
: > "${STUBS}/sessions"
run_guard

if ! acted; then
    fail "no session ever appeared and the guard did not repair"
    sed 's/^/       /' "${ROOT}/said.txt"
elif ! copies_gone; then
    fail "it restarted the login screen but left the display files in place"
else
    pass "no graphical session in the whole watch: it removed both files and restarted"
fi

# ==============================================================================
echo ""
echo "== ⚠️ THE 2026-09-05 CASE: a session exists and the screen is black =="
# ==============================================================================
# This is the one the old guard got wrong, and it is the reason this file
# exists. There IS a session — the compositor is running, the pointer moves —
# and the screen is black because the compositor could not use the display
# arrangement we handed it. The old check said "a session exists, therefore the
# login screen is up" and stopped there.
#
# The evidence the guard now uses is the compositor's own complaint in the
# journal, which names the display configuration as the thing it could not use.
scenario blackscreen
printf 'c1\nc1\nc1\nc1\n' > "${STUBS}/sessions"
cat > "${STUBS}/journal" << 'JOURNAL'
gnome-shell[1442]: Failed to apply monitors config: Both monitors are not adjacent
gdm[1201]: Greeter session opened
JOURNAL
run_guard

if ! acted; then
    fail "THE 2026-09-05 BUG IS BACK: a session existed, the compositor said it"
    fail "could not use the display arrangement, and the guard did nothing"
    sed 's/^/       /' "${ROOT}/said.txt"
elif ! copies_gone; then
    fail "it restarted the login screen but left the files that caused it"
else
    pass "a session exists but the compositor rejected the arrangement: it repaired"
fi

# ==============================================================================
echo ""
echo "== a login screen that keeps crashing and restarting =="
# ==============================================================================
# The other shape of the same failure, and invisible to any yes-or-no question
# about sessions: at every single instant there IS one. It is a different one
# each time.
scenario churn
printf 'c1\nc1\nc4\nc7\n' > "${STUBS}/sessions"
run_guard

if ! acted; then
    fail "the session was replaced twice during the watch and the guard did nothing"
    sed 's/^/       /' "${ROOT}/said.txt"
else
    pass "the session kept being replaced: it repaired"
fi

# systemd counts the restarts too, and that is a second, independent way to see
# the same thing — worth having, because a crash fast enough to leave no session
# behind at look time still bumps the counter.
scenario restarts
printf 'c1\nc1\nc1\nc1\n' > "${STUBS}/sessions"
printf '0\n3\n' > "${STUBS}/nrestarts"
run_guard

if ! acted; then
    fail "gdm.service restarted three times during the watch and the guard did nothing"
    sed 's/^/       /' "${ROOT}/said.txt"
else
    pass "gdm.service's restart count went up during the watch: it repaired"
fi

# A session that appeared and then went away. The same failure as one that never
# appeared, and it must not be read as "it came up" just because it once did.
scenario vanished
printf 'c1\nc1\n\n' > "${STUBS}/sessions"
run_guard

if ! acted; then
    fail "the session appeared and then vanished and the guard did nothing"
    sed 's/^/       /' "${ROOT}/said.txt"
else
    pass "the session appeared and then vanished: it repaired"
fi

# ==============================================================================
echo ""
echo "== the things that make it stand aside =="
# ==============================================================================
# A safety net that acts when it should not is its own fault. Each of these must
# stop it dead, before it waits or touches anything.

# ⚠️ THIS IS THE STATE OF EVERY DEFAULT AQUARIUSOS MACHINE since 2026-09-05: the
# login screen is handed no display arrangement, so there is nothing here for the
# guard to remove. It must stand aside — and it must SAY so, loudly, which the
# next case checks.
scenario no-copies
rm -f "${ROOT}/etc/xdg/monitors.xml" "${ROOT}/var/lib/gdm/.config/monitors.xml"
: > "${STUBS}/sessions"
run_guard
if acted; then
    fail "there was nothing to take away and it restarted the login screen anyway"
else
    pass "no copied display file: it does not restart anything"
fi

# ==============================================================================
echo ""
echo "== ⚠️ the journal must answer 'did the guard restart my login screen?' =="
# ==============================================================================
# WHY THIS TEST EXISTS. On the night of 2026-09-05, with the login screen black
# and the greeter's journal showing Xwayland lost about sixty seconds in, the
# first question was whether this program had restarted GDM and produced what
# Royce was looking at. Answering it meant reading the guard's source to work out
# which of its several quiet exits it had taken — at the exact moment nobody has
# time to read source.
#
# So every path that changes nothing must print one greppable phrase, and the
# repair path must print the other. Two phrases, no third possibility:
#
#     journalctl -b -u aquarius-gdm-guard.service
#
# ⚠️ IF YOU CHANGE THESE WORDS, CHANGE THEM IN docs/restart/login.md TOO — that
# is where the command and the two phrases are written down for Royce.
scenario quiet-exit-is-loud
rm -f "${ROOT}/etc/xdg/monitors.xml" "${ROOT}/var/lib/gdm/.config/monitors.xml"
: > "${STUBS}/sessions"
run_guard
if grep -q "DID NOT TOUCH THE LOGIN SCREEN" "${ROOT}/said.txt"; then
    pass "standing aside says 'DID NOT TOUCH THE LOGIN SCREEN' in the journal"
else
    fail "it stood aside without saying so — the journal cannot answer 'was it you?'"
    sed 's/^/       /' "${ROOT}/said.txt"
fi

# The healthy machine must say it too. This is the OTHER quiet exit — the one at
# the very end, after a full watch — and it is the one somebody debugging a slow
# boot will actually be looking at.
scenario quiet-exit-is-loud-healthy
printf 'c1\nc1\nc1\nc1\n' > "${STUBS}/sessions"
run_guard
if grep -q "DID NOT TOUCH THE LOGIN SCREEN" "${ROOT}/said.txt"; then
    pass "a healthy watch also says 'DID NOT TOUCH THE LOGIN SCREEN'"
else
    fail "the healthy path stayed quiet — the journal cannot answer 'was it you?'"
    sed 's/^/       /' "${ROOT}/said.txt"
fi

# And the repair must NOT say it, or the phrase means nothing.
scenario repair-does-not-claim-innocence
: > "${STUBS}/sessions"
run_guard
if grep -q "DID NOT TOUCH THE LOGIN SCREEN" "${ROOT}/said.txt"; then
    fail "it repaired the machine and still said it had not touched the login screen"
    sed 's/^/       /' "${ROOT}/said.txt"
elif grep -q "REPAIRING THE LOGIN SCREEN" "${ROOT}/said.txt"; then
    pass "a real repair says 'REPAIRING THE LOGIN SCREEN' and never the other phrase"
else
    fail "a repair happened and the journal says neither phrase"
    sed 's/^/       /' "${ROOT}/said.txt"
fi

scenario already-acted
: > "${STUBS}/sessions"
: > "${ROOT}/run/aquarius/gdm-guard-acted"
run_guard
if acted; then
    fail "it acted twice in one boot — the stamp under /run did not stop it"
else
    pass "it had already acted this boot: it did nothing"
fi

scenario greetd
: > "${STUBS}/sessions"
: > "${STUBS}/gdm-not-enabled"
run_guard
if acted; then
    fail "GDM is not the login screen here and it restarted gdm anyway"
else
    pass "GDM is not in use: it stands aside"
fi

# An automatic login is a machine with no greeter session by design. Treating
# that as a failure would restart the login screen out from under somebody who
# was already logged in.
scenario autologin
: > "${STUBS}/sessions"
echo active > "${STUBS}/gdm-user-state"
run_guard
if acted; then
    fail "it treated an automatic login as a failure"
    sed 's/^/       /' "${ROOT}/said.txt"
else
    pass "no graphical session but the gdm user has one: it stands aside"
fi

# ==============================================================================
echo ""
echo "== it says what it did, where a person can find it =="
# ==============================================================================
# The log is the only explanation anybody gets for "why is my login screen a
# different size than I left it".
scenario logging
: > "${STUBS}/sessions"
run_guard
LOG="${ROOT}/var/lib/aquarius/gdm-display.log"
if [ ! -s "${LOG}" ]; then
    fail "it repaired the machine and wrote nothing down"
elif grep -q "REPAIRING THE LOGIN SCREEN" "${LOG}"; then
    pass "it wrote down that it repaired the login screen, and why"
    sed 's/^/       /' "${LOG}" | head -5
else
    fail "the log does not say a repair happened"
    sed 's/^/       /' "${LOG}"
fi

# ==============================================================================
echo ""
echo "== the rules that cannot be checked by running it =="
# ==============================================================================
if bash -n "${GUARD}"; then
    pass "the guard is valid shell"
else
    fail "the guard does not parse as shell"
fi

# The stamp is what makes a repair happen at most once per boot. It has to live
# under /run, which is emptied at every boot — a stamp under /var would mean the
# guard repairs once in the machine's life and never again.
if grep -q '^AQ_STAMP_DIR="/run/' "${GUARD}"; then
    pass "its 'already tried' stamp is under /run, so it resets at each boot"
else
    fail "the guard's stamp is not under /run — it would only ever repair once, ever"
fi

# ⚠️ THE REGRESSION GUARD. The failure of 2026-09-05 was a single yes-or-no
# question about sessions. If a helper with that shape ever comes back, this
# catches it in the source, because a wrong answer to it is invisible at runtime.
if grep -q 'aq_login_screen_is_up\|aq_graphical_session_exists' "${GUARD}"; then
    fail "the guard is back to asking 'is there a session?' — that is the 2026-09-05 bug"
else
    pass "the guard does not decide on session existence alone"
fi

echo ""
echo "  passed ${PASSED}, failed ${FAILED}"
if [ "${FAILED}" -ne 0 ]; then
    echo "  The guard that is supposed to rescue a black login screen would not"
    echo "  rescue it. See docs/restart/login.md."
    exit 1
fi
echo "  The guard acts when the login screen is broken and only then."
exit 0
