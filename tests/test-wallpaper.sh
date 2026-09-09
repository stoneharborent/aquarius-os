#!/usr/bin/bash
# =============================================================================
# test-wallpaper.sh — the wallpaper follows light and dark, and breaks nothing
# =============================================================================
# WHAT THIS PROVES, AND WHY IT IS WORTH A TEST OF ITS OWN
#
# /usr/libexec/aquarius-wallpaper is what makes the desktop picture follow the
# light/dark flip. It runs at every login, and it runs again every time somebody
# flips the theme — so it is one of the few programs on this machine that runs
# BEFORE there is a desktop to show an error on.
#
# That is the whole reason for this file. Three of the things it does are easy
# to get wrong and impossible to notice going wrong:
#
#   * IT MUST STOP ONLY ITS OWN swaybg. The lazy version of this program is
#     `pkill swaybg`, and it works perfectly until the day somebody is running a
#     swaybg of their own — for a second screen, for a presentation — and our
#     theme flip kills it. That would look like a bug in THEIR program.
#   * IT MUST REPLACE, NOT PILE UP. A flip that leaves the old swaybg running
#     and starts a new one on top gives a desktop with two wallpapers fighting
#     over it, and a machine that grows one more of them per flip.
#   * IT MUST NEVER EXIT NON-ZERO. A missing picture or a missing swaybg is
#     decoration failing. Decoration must not be able to take a login down.
#
# HOW IT IS TESTED WITHOUT A SCREEN
#
# On a build machine there is no compositor, no appearance portal and no swaybg.
# The program has three test hooks for exactly this, and none of them changes
# what it DECIDES — only where it looks:
#
#   AQ_WALLPAPER_SWAYBG       run this instead of `swaybg`
#   AQ_WALLPAPER_DIR          take the pictures from here
#   AQ_WALLPAPER_FAKE_PORTAL  use this text instead of asking the portal
#
# The stand-in swaybg writes down every argument it was given and then sleeps,
# so it is a real process with a real pid that the program has to find and stop
# the same way it would find and stop the real one. It is deliberately NOT
# `exec`ed into `sleep`: the name Linux records for a process (/proc/<pid>/comm)
# is what the program checks before killing anything, and an exec would change
# that name to `sleep` and quietly switch the check off.
#
# HOW TO RUN IT
#   ./tests/test-wallpaper.sh
#   ./tests/test-wallpaper.sh /usr/libexec/aquarius-wallpaper
# =============================================================================

set -uo pipefail

PROG="${1:-}"
if [ -z "${PROG}" ]; then
    PROG="$(cd "$(dirname "$0")/.." && pwd)/system_files/usr/libexec/aquarius-wallpaper"
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
cleanup() {
    # Anything still running from this test, gone. Read from the files rather
    # than pkill'd by name, for the same reason the program under test does it.
    for f in "${WORK}"/pids/*; do
        [ -r "${f}" ] || continue
        kill "$(cat "${f}" 2> /dev/null)" 2> /dev/null || true
    done
    kill "$(cat "${WORK}/run/aquarius-wallpaper.pid" 2> /dev/null)" 2> /dev/null || true
    rm -rf "${WORK}"
}
trap cleanup EXIT

mkdir -p "${WORK}/bin" "${WORK}/pics" "${WORK}/run" "${WORK}/pids"

# -----------------------------------------------------------------------------
# The stand-in swaybg
# -----------------------------------------------------------------------------
# It writes its arguments into ${WORK}/args, one run per line, and then waits to
# be killed. It is put on PATH under the name `swaybg` so that the program finds
# it the ordinary way, through `command -v swaybg`, with no override at all —
# which means the default path through the code is the one being tested.
#
# ⚠️ THE TWO ODD-LOOKING LINES IN IT ARE BOTH LOAD-BEARING, AND THE SECOND ONE
# COST AN HOUR. The obvious stand-in is three lines — record the arguments, then
# `sleep 600` — and it passes every check in this file when you run it at a
# terminal. Run it with its output CAPTURED, which is what CI does and what
# `out=$(./tests/test-wallpaper.sh)` does, and it hangs for ten minutes.
#
#   1. `exec > /dev/null 2>&1 < /dev/null` — a stand-in inherits the pipe that
#      the output is being captured through, and anything holding that pipe open
#      keeps the capture waiting, long after the test has printed its last line.
#   2. the sleep is BACKGROUNDED and taken down by a trap, rather than run in the
#      foreground. When this script is killed while a foreground `sleep` is
#      running, bash dies and the sleep does not: it is orphaned and runs on. The
#      test's own checks would still pass — the process it looked for really is
#      gone — while a stray sleep sat there for ten minutes holding things open.
#
# It is deliberately NOT `exec`ed into `sleep`, which would solve both problems
# at once and break the test: the name Linux records for a process is what the
# program under test checks before killing anything, and an exec would change
# that name from `swaybg` to `sleep` and quietly switch the check off.
cat > "${WORK}/bin/swaybg" <<'STANDIN'
#!/usr/bin/bash
printf '%s\n' "$*" >> "${AQ_TEST_ARGS}"
exec > /dev/null 2>&1 < /dev/null
sleep 600 &
aq_sleeper=$!
trap 'kill "${aq_sleeper}" 2> /dev/null; exit 0' TERM INT
wait "${aq_sleeper}"
STANDIN
chmod 0755 "${WORK}/bin/swaybg"

export AQ_TEST_ARGS="${WORK}/args"
PATH="${WORK}/bin:${PATH}"
export PATH

# The two pictures, empty but present: the program checks that it can READ them,
# never what is inside, and a real 4K PNG in this repository's test folder would
# be eight megabytes to prove nothing.
ICE="${WORK}/pics/the-pour-ice-3840x2160.png"
MIDNIGHT="${WORK}/pics/the-pour-midnight-3840x2160.png"
: > "${ICE}"
: > "${MIDNIGHT}"
export AQ_WALLPAPER_DIR="${WORK}/pics"

# The pid file must land somewhere this test can look at, and be gone with the
# rest of it afterwards.
export XDG_RUNTIME_DIR="${WORK}/run"
PID_FILE="${WORK}/run/aquarius-wallpaper.pid"

# ⚠️ AQ_LOG IS SET HERE ON PURPOSE, AND NOT LEFT ALONE.
# This test is very often run FROM an Aquarius session, where AQ_LOG already
# names the real ~/.local/state/aquarius-session/session.log. Inheriting it
# would send every sentence this test wants to read into the log of the desktop
# the tester is sitting in, and the test would see nothing and report that the
# program says nothing.
export AQ_LOG="${WORK}/log"

# The scheme note lives beside the pid file.
SCHEME_FILE="${WORK}/run/aquarius-wallpaper.scheme"

run() { # run <arguments...>  — returns the program's exit status
    : > "${AQ_LOG}"
    "${PROG}" "$@" > "${WORK}/out" 2>&1
}

log() { cat "${AQ_LOG}" 2> /dev/null; }
args() { cat "${AQ_TEST_ARGS}" 2> /dev/null; }
last_arg_line() { tail -1 "${AQ_TEST_ARGS}" 2> /dev/null; }
alive() { [ -n "${1:-}" ] && [ -d "/proc/$1" ]; }

reset() {
    kill "$(cat "${PID_FILE}" 2> /dev/null)" 2> /dev/null || true
    rm -f "${PID_FILE}" "${SCHEME_FILE}" "${AQ_TEST_ARGS}"
    : > "${AQ_TEST_ARGS}"
}

echo "== the wallpaper follows light and dark =="
echo "   program under test: ${PROG}"

# -----------------------------------------------------------------------------
# 1. It starts swaybg with the arguments the design says
# -----------------------------------------------------------------------------
# -c '#0B1220' is the palette's navy ground, so the hand-off from the boot
# animation has no flash of grey in it. -m fill crops to the screen rather than
# stretching, so a 16:9 picture on a 16:10 monitor loses a little top and bottom
# instead of everybody looking short. Both are decisions, so both are checked.
reset
if run ice; then
    ok "asking for ice exits 0"
else
    bad "asking for ice exited non-zero — a login could be taken down by a wallpaper"
fi

line="$(last_arg_line)"
case "${line}" in
    *"-i ${ICE}"*) ok "it drew the ICE picture: ${ICE##*/}" ;;
    *) bad "it did not name the ice picture. swaybg was given: ${line}" ;;
esac
case "${line}" in
    *"-c #0B1220"*) ok "the colour behind the picture is the palette's navy ground" ;;
    *) bad "the ground colour is not #0B1220. swaybg was given: ${line}" ;;
esac
case "${line}" in
    *"-m fill"*) ok "the picture is cropped to the screen, not stretched (-m fill)" ;;
    *) bad "the fill mode is not 'fill'. swaybg was given: ${line}" ;;
esac

if log | grep -q 'showing the ice wallpaper'; then
    ok "and it says what it did, in one plain line"
else
    bad "nothing in the log says a wallpaper went up. It said: $(log)"
fi

ICE_PID="$(cat "${PID_FILE}" 2> /dev/null)"
if alive "${ICE_PID}"; then
    ok "the pid it wrote down (${ICE_PID}) is a real, running swaybg"
else
    bad "the pid file does not name a running process — nothing could ever stop it again"
fi

# -----------------------------------------------------------------------------
# 2. ⚠️ THE LOAD-BEARING ONE: a flip REPLACES, it does not pile up
# -----------------------------------------------------------------------------
if run midnight; then
    ok "flipping to midnight exits 0"
else
    bad "flipping to midnight exited non-zero"
fi

MID_PID="$(cat "${PID_FILE}" 2> /dev/null)"

if [ -n "${MID_PID}" ] && [ "${MID_PID}" != "${ICE_PID}" ]; then
    ok "the pid file now names a different swaybg (${ICE_PID} -> ${MID_PID})"
else
    bad "the pid file still says ${ICE_PID} — the flip did not start a new wallpaper"
fi

if alive "${ICE_PID}"; then
    bad "⚠️ the OLD swaybg (${ICE_PID}) is still running — two wallpapers are now fighting over the screen, and every flip would add another"
else
    ok "the old swaybg is gone: a flip swaps the picture, it does not stack them"
fi

if alive "${MID_PID}"; then
    ok "the new one (${MID_PID}) is up"
else
    bad "the new swaybg is not running — the desktop would be a flat colour"
fi

case "$(last_arg_line)" in
    *"-i ${MIDNIGHT}"*) ok "and it is drawing the MIDNIGHT picture" ;;
    *) bad "the new swaybg is not drawing the midnight picture: $(last_arg_line)" ;;
esac

if [ "$(args | wc -l)" -eq 2 ]; then
    ok "exactly two swaybgs were ever started, one per call"
else
    bad "swaybg was started $(args | wc -l) times for two calls"
fi

# -----------------------------------------------------------------------------
# 3. ⚠️ IT STOPS ONLY ITS OWN. Somebody else's swaybg is not ours to kill.
# -----------------------------------------------------------------------------
# This is the case `pkill swaybg` gets wrong, and the reason the pid file exists
# at all. A second swaybg is started here BY HAND — it is nothing to do with the
# program under test and its pid is in no file of ours — and it has to survive a
# flip untouched.
"${WORK}/bin/swaybg" --somebody-elses-screen &
STRANGER=$!
echo "${STRANGER}" > "${WORK}/pids/stranger"
sleep 0.2

if run ice; then
    ok "a flip with a stranger's swaybg running still exits 0"
else
    bad "it exited non-zero with another swaybg on the machine"
fi

if alive "${STRANGER}"; then
    ok "⚠️ somebody else's swaybg (${STRANGER}) was left alone — this is the check that stops 'pkill swaybg' coming back"
else
    bad "⚠️ it killed a swaybg it did not start (${STRANGER}). Somebody's second screen or presentation would go black, and it would look like a bug in THEIR program."
fi

# And the belt to that pair of braces: no line of this program may RUN pkill.
# The comments are allowed to say the word — the header says it in capitals —
# so the comments are stripped off before looking.
if ! sed 's/#.*//' "${PROG}" | grep -q 'pkill'; then
    ok "and no line of the program runs 'pkill' at all"
else
    bad "the program has a line that runs 'pkill'. Read its header before leaving that there:"
    sed 's/#.*//' "${PROG}" | grep -n 'pkill' | sed 's/^/       /' >&2
fi

reset
kill "${STRANGER}" 2> /dev/null || true
wait "${STRANGER}" 2> /dev/null || true

# -----------------------------------------------------------------------------
# 4. A pid file that names something that is NOT swaybg
# -----------------------------------------------------------------------------
# A pid file outlives the program it names, and Linux hands the number out
# again. So the file alone is never enough: the program also asks the kernel
# what that process actually is. Here the pid file is poisoned with the pid of
# an ordinary `sleep`, which must survive.
sleep 600 &
INNOCENT=$!
echo "${INNOCENT}" > "${WORK}/pids/innocent"
echo "${INNOCENT}" > "${PID_FILE}"

if run midnight; then
    ok "a stale pid file does not stop it working"
else
    bad "it exited non-zero on a stale pid file"
fi

if alive "${INNOCENT}"; then
    ok "the pid file named an innocent process and it was NOT killed"
else
    bad "it killed the process the pid file named without checking what it was"
fi
kill "${INNOCENT}" 2> /dev/null || true
wait "${INNOCENT}" 2> /dev/null || true
reset

# -----------------------------------------------------------------------------
# 5. `auto` asks the portal, and reads every shape of answer it can give
# -----------------------------------------------------------------------------
# The three values are from the freedesktop specification: 0 no preference,
# 1 dark, 2 light. The two spellings are the two D-Bus methods — `ReadOne`
# returns the number, the older `Read` wraps it in one more layer. Both are
# tried on a real machine, so both are parsed here.
#
# ⚠️ 0 MEANS ICE. A computer with no preference is a computer in the default
# look of AquariusOS, which is the light one — not "do nothing".
check_auto() { # check_auto <portal text> <expected scheme> <what it is>
    reset
    if AQ_WALLPAPER_FAKE_PORTAL="$1" "${PROG}" auto > "${WORK}/out" 2>&1; then
        got="$(cat "${SCHEME_FILE}" 2> /dev/null)"
        if [ "${got}" = "$2" ]; then
            ok "auto: $3 -> ${2}"
        else
            bad "auto: $3 should have given ${2}, and gave '${got}'"
        fi
    else
        bad "auto: $3 made it exit non-zero"
    fi
}

check_auto '(<uint32 1>,)' midnight "the portal says dark (ReadOne)"
check_auto '(<uint32 2>,)' ice "the portal says light (ReadOne)"
check_auto '(<uint32 0>,)' ice "the portal says no preference"
check_auto '(<<uint32 1>>,)' midnight "the portal says dark (the older Read)"

# An answer nobody can read must not be a crash and must not be a black screen:
# it falls through to the machine's own setting, and then to ice.
reset
if AQ_WALLPAPER_FAKE_PORTAL='nonsense from a future glib' \
    "${PROG}" auto > "${WORK}/out" 2>&1; then
    ok "auto: an answer it cannot read still exits 0"
else
    bad "auto: an unreadable portal answer made it exit non-zero"
fi
if [ -s "${SCHEME_FILE}" ]; then
    ok "auto: and it still put a wallpaper up ($(cat "${SCHEME_FILE}"))"
else
    bad "auto: an unreadable answer left the desktop with no wallpaper at all"
fi

# A word it does not know — from a hand, or from some future shell — is the same
# rule: say so, work it out, carry on.
reset
if AQ_WALLPAPER_FAKE_PORTAL='(<uint32 1>,)' \
    "${PROG}" purple > "${WORK}/out" 2>&1; then
    ok "a scheme it does not know exits 0 rather than leaving a bare desktop"
else
    bad "an unknown scheme name made it exit non-zero"
fi
if grep -q 'is not a theme I know' "${WORK}/out" || log | grep -q 'is not a theme I know'; then
    ok "and it says so plainly instead of failing silently"
else
    bad "it did not say that it had been handed a word it does not know"
fi
if [ "$(cat "${SCHEME_FILE}" 2> /dev/null)" = "midnight" ]; then
    ok "and it fell back to what the portal says (midnight)"
else
    bad "it did not fall back to the portal's answer: '$(cat "${SCHEME_FILE}" 2> /dev/null)'"
fi

# -----------------------------------------------------------------------------
# 6. A missing picture — one sentence, exit 0, and the old one LEFT UP
# -----------------------------------------------------------------------------
# The wrong wallpaper is better than no wallpaper, and it is a great deal better
# than flat grey. So if the picture being asked for is not on the machine, the
# swaybg that is already running is not touched.
reset
run ice
KEEPER="$(cat "${PID_FILE}" 2> /dev/null)"
mv "${MIDNIGHT}" "${WORK}/midnight-put-away.png"

if run midnight; then
    ok "a missing picture exits 0"
else
    bad "⚠️ a missing picture exited non-zero — that is a wallpaper taking a login down"
fi

if log | grep -q 'not on this computer'; then
    ok "and it says which picture is missing, in one plain sentence"
else
    bad "a missing picture was silent. It said: $(log)"
fi

if alive "${KEEPER}"; then
    ok "the wallpaper that was already up was left alone (${KEEPER})"
else
    bad "it stopped the wallpaper that was up and could not replace it — the desktop is now flat grey"
fi

if [ "$(args | wc -l)" -eq 1 ]; then
    ok "and it started no new swaybg"
else
    bad "it started a swaybg for a picture that does not exist"
fi
mv "${WORK}/midnight-put-away.png" "${MIDNIGHT}"
reset

# -----------------------------------------------------------------------------
# 7. No swaybg on the machine at all — one sentence, exit 0
# -----------------------------------------------------------------------------
# The image always installs swaybg (build_files/55-aquarius-session.sh) so this
# should never happen on a real machine. It is checked because the cost of being
# wrong is the whole login, and the cost of the check is four lines.
reset
if AQ_WALLPAPER_SWAYBG="${WORK}/bin/no-such-swaybg" \
    "${PROG}" ice > "${WORK}/out" 2>&1; then
    ok "no swaybg on the machine: it exits 0"
else
    bad "⚠️ a missing swaybg exited non-zero — no wallpaper would mean no login"
fi
if log | grep -q 'not installed'; then
    ok "and it says the desktop will be a flat colour and everything else works"
else
    bad "a missing swaybg was silent. It said: $(log)"
fi

# -----------------------------------------------------------------------------
# 8. --status only looks
# -----------------------------------------------------------------------------
reset
before="$(args | wc -l)"
if AQ_WALLPAPER_FAKE_PORTAL='(<uint32 1>,)' \
    "${PROG}" --status > "${WORK}/out" 2>&1; then
    ok "--status exits 0"
else
    bad "--status exited non-zero"
fi
if [ "$(args | wc -l)" -eq "${before}" ]; then
    ok "--status changes nothing; it started no swaybg"
else
    bad "--status started a wallpaper"
fi
if grep -q "would use midnight" "${WORK}/out"; then
    ok "--status says what 'auto' would do right now, and why"
else
    bad "--status did not say what auto would choose. It said: $(cat "${WORK}/out")"
fi

echo ""
if [ "${fails}" -ne 0 ]; then
    echo "::error::The wallpaper setter is not safe (${fails} check(s) failed)."
    echo "This program runs at every login and at every light/dark flip. A fault"
    echo "here is a desktop with no picture, two pictures, or a login that stops."
    echo "See docs/restart/desktop-identity.md and the header of the program."
    exit 1
fi
echo "All wallpaper checks passed."
