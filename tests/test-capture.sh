#!/usr/bin/env bash
# ==============================================================================
# Tests for aquarius-capture — screenshots and screen recording
# ==============================================================================
# WHAT THIS PROGRAM IS, AND WHY IT IS WORTH TESTING
#
# /usr/libexec/aquarius-capture is the one program behind every screenshot and
# every screen recording on AquariusOS. Two buttons in the top bar run it, six
# keyboard shortcuts run it, and a service runs it once per login to make the
# Screenshots folder.
#
# The top bar is written against its exact wording, so the things that must
# never change are the things checked hardest here:
#
#   * `status` prints JSON and exits 0. ALWAYS. With no session, no runtime
#     folder, a recording that died, a state file full of nonsense — every one
#     of those is a case where a non-zero exit would show as a broken indicator
#     in the bar and nothing else.
#   * `folder` prints the Screenshots path and creates it.
#   * the file names are `Screenshot 2026-09-13 at 14.02.11.png` exactly.
#   * `record` writes the agreed state file and `record stop` removes it.
#   * the Files sidebar pin is added ONCE and never fought over.
#
# ------------------------------------------------------------------------------
# HOW THE FAKING WORKS
# ------------------------------------------------------------------------------
# Nothing here needs a screen, a compositor, root, or a graphics card. The four
# real tools are replaced by fakes earlier on the PATH:
#
#   slurp         prints a rectangle instead of drawing an overlay
#   grim          writes a few bytes to the file it was given
#   wf-recorder   ⚠️ THE INTERESTING ONE. It behaves like the real recorder in
#                 the two ways that matter: it creates its output file
#                 immediately (so the "has it really started?" wait succeeds)
#                 and it catches an interrupt and writes a proper ending before
#                 exiting (so "did stop finalise the file?" means something).
#   wl-copy,
#   notify-send,
#   ffmpeg        do nothing, quietly.
#
# and HOME, XDG_CONFIG_HOME, XDG_STATE_HOME and XDG_RUNTIME_DIR all point into
# one temporary folder, so no test touches the machine it runs on.
#
# HOW TO RUN IT
#   ./tests/test-capture.sh
#   ./tests/test-capture.sh /usr/libexec/aquarius-capture   (the installed copy)
# ==============================================================================

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
HELPER="${1:-${HERE}/../system_files/usr/libexec/aquarius-capture}"

if [ ! -r "${HELPER}" ]; then
    echo "test-capture: cannot read ${HELPER}" >&2
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
# The fake tools
# ------------------------------------------------------------------------------
mkdir -p "${WORK}/bin"

# slurp: prints whatever rectangle the test asked for, or fails (which is how
# the real slurp reports "the person pressed Escape").
cat > "${WORK}/bin/slurp" << 'EOF'
#!/usr/bin/env bash
if [ -n "${FAKE_SLURP_CANCEL:-}" ]; then exit 1; fi
echo "${FAKE_SLURP_GEOMETRY:-0,0 1920x1080}"
EOF

# grim: the last argument is the file to write. Writes real bytes unless the
# test asks it to produce an empty file (the "clicked instead of dragging"
# case, which the helper has to notice and clean up).
cat > "${WORK}/bin/grim" << 'EOF'
#!/usr/bin/env bash
out=""
for a in "$@"; do out="$a"; done
if [ -n "${FAKE_GRIM_EMPTY:-}" ]; then : > "$out"; else printf 'PNG-ish' > "$out"; fi
EOF

# wf-recorder: -f names the file. Creates it at once, then waits; on an
# interrupt it appends an ending and exits, exactly as the real one finalises
# an MP4. FAKE_RECORDER_DIE makes it fall over immediately instead.
cat > "${WORK}/bin/wf-recorder" << 'EOF'
#!/usr/bin/env bash
out=""
while [ $# -gt 0 ]; do
    case "$1" in -f) out="$2"; shift 2 ;; *) shift ;; esac
done
if [ -n "${FAKE_RECORDER_DIE:-}" ]; then echo "no such encoder" >&2; exit 1; fi
printf 'MP4' > "$out"
finish() { printf 'END' >> "$out"; exit 0; }
trap finish INT TERM
while true; do sleep 0.05; done
EOF

for quiet in wl-copy notify-send ffmpeg xdg-open; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "${WORK}/bin/${quiet}"
done

chmod +x "${WORK}"/bin/*
export PATH="${WORK}/bin:${PATH}"

# ------------------------------------------------------------------------------
# A fresh, private home for each group of checks
# ------------------------------------------------------------------------------
fresh_home() {
    local h="${WORK}/home-$1"
    rm -rf "${h}"
    mkdir -p "${h}/run"
    export HOME="${h}"
    export XDG_CONFIG_HOME="${h}/.config"
    export XDG_STATE_HOME="${h}/.local/state"
    export XDG_RUNTIME_DIR="${h}/run"
}

run() { bash "${HELPER}" "$@"; }

# ==============================================================================
# 1. `folder` — the Screenshots folder
# ==============================================================================
echo "The Screenshots folder"
fresh_home folder

OUT="$(run folder)"
if [ "${OUT}" = "${HOME}/Screenshots" ]; then
    pass "folder prints ~/Screenshots"
else
    fail "folder printed '${OUT}', expected '${HOME}/Screenshots'"
fi
if [ -d "${HOME}/Screenshots" ]; then
    pass "folder creates it when it is not there"
else
    fail "folder did not create ${HOME}/Screenshots"
fi

# If somebody has pointed XDG_SCREENSHOTS_DIR somewhere else, that wins — or our
# tool and GNOME's would save to two different places.
mkdir -p "${XDG_CONFIG_HOME}"
# shellcheck disable=SC2016  # the literal text $HOME is what user-dirs.dirs contains
echo 'XDG_SCREENSHOTS_DIR="$HOME/Elsewhere"' > "${XDG_CONFIG_HOME}/user-dirs.dirs"
OUT="$(run folder)"
if [ "${OUT}" = "${HOME}/Elsewhere" ]; then
    pass "a XDG_SCREENSHOTS_DIR in user-dirs.dirs is obeyed (GNOME writes one too)"
else
    fail "user-dirs.dirs said Elsewhere and folder printed '${OUT}'"
fi

# ==============================================================================
# 2. `shot` — the picture, and its name
# ==============================================================================
echo "Taking a picture"
fresh_home shot

OUT="$(run shot area)"
if [ -s "${OUT}" ]; then
    pass "shot area saved a file and printed its path"
else
    fail "shot area printed '${OUT}', which is not a file with anything in it"
fi

# ⚠️ THE FILE NAME IS PART OF THE FEATURE. Royce asked for Mac-style names, and
# a person sorting a folder by name is sorting by time only if this shape holds.
NAME="$(basename "${OUT}")"
if [[ "${NAME}" =~ ^Screenshot\ [0-9]{4}-[0-9]{2}-[0-9]{2}\ at\ [0-9]{2}\.[0-9]{2}\.[0-9]{2}\.png$ ]]; then
    pass "it is named '${NAME}' — Mac style, to the second"
else
    fail "the name '${NAME}' is not 'Screenshot YYYY-MM-DD at HH.MM.SS.png'"
fi

# Full stops, never colons: a colon in a file name breaks the moment the file is
# copied to a Windows machine, a memory card or a NAS.
case "${NAME}" in
    *:*) fail "the name contains a colon, which is unusable off Linux" ;;
    *) pass "no colons in the name" ;;
esac

# Two captures inside the same second must not silently replace one another.
A="$(run shot area)"
B="$(run shot area)"
if [ "${A}" != "${B}" ] && [ -s "${A}" ] && [ -s "${B}" ]; then
    pass "two captures in the same second are two files, not one"
else
    fail "a second capture overwrote the first ('${A}' vs '${B}')"
fi

# Escape is a cancellation, not a fault: nothing saved, nothing said, exit 0.
BEFORE="$(find "${HOME}/Screenshots" -type f | wc -l)"
FAKE_SLURP_CANCEL=1 run shot area > /dev/null 2>&1
RC=$?
AFTER="$(find "${HOME}/Screenshots" -type f | wc -l)"
if [ "${RC}" -eq 0 ] && [ "${BEFORE}" = "${AFTER}" ]; then
    pass "pressing Escape saves nothing and is not an error"
else
    fail "cancelling exited ${RC} and the file count went ${BEFORE} -> ${AFTER}"
fi

# ⚠️ AN EMPTY PICTURE MUST NOT BE LEFT LYING ABOUT. grim exits 0 having written
# nothing when the rectangle had no size (a click rather than a drag).
BEFORE="$(find "${HOME}/Screenshots" -type f | wc -l)"
FAKE_GRIM_EMPTY=1 run shot area > /dev/null 2>&1
RC=$?
AFTER="$(find "${HOME}/Screenshots" -type f | wc -l)"
if [ "${RC}" -ne 0 ] && [ "${BEFORE}" = "${AFTER}" ]; then
    pass "an empty capture is reported and the empty file is removed"
else
    fail "an empty capture exited ${RC} and left ${AFTER} files (was ${BEFORE})"
fi

# ==============================================================================
# 3. `status` — the one the bar asks once a second
# ==============================================================================
# ⚠️ THIS IS THE MOST IMPORTANT GROUP IN THE FILE. The bar parses whatever comes
# back, once a second, forever. There is no situation in which a non-zero exit
# or a non-JSON answer is acceptable.
echo "status, in every state it can be asked in"
fresh_home status

check_status_json() { # check_status_json "<description>"
    local out rc
    out="$(run status 2>&1)"
    rc=$?
    if [ "${rc}" -ne 0 ]; then
        fail "status exited ${rc} $1"
        return
    fi
    case "${out}" in
        '{"recording":'*'"elapsed":'*'}')
            pass "status answered JSON and exited 0 $1"
            ;;
        *)
            fail "status said '${out}' $1"
            ;;
    esac
}

check_status_json "with nothing recording"

OUT="$(run status)"
case "${OUT}" in
    '{"recording":false,"started":0,"file":"","elapsed":0}') pass "the not-recording answer is exactly the agreed one" ;;
    *) fail "the not-recording answer was '${OUT}'" ;;
esac

# No runtime folder at all — what a program run from cron or a broken session
# sees.
SAVED_RUNTIME="${XDG_RUNTIME_DIR}"
unset XDG_RUNTIME_DIR
check_status_json "with no XDG_RUNTIME_DIR at all"
export XDG_RUNTIME_DIR="${SAVED_RUNTIME}"

# A state file full of nonsense. This is what a half-written file after a power
# cut looks like, and it must not take the bar down with it.
mkdir -p "${XDG_RUNTIME_DIR}/aquarius-capture"
echo 'not json at all {{{' > "${XDG_RUNTIME_DIR}/aquarius-capture/recording.json"
check_status_json "with a corrupt state file"

# A state file naming a process that is long gone — the "the recorder crashed"
# case. status must say false AND tidy the file away, so the next recording
# starts clean.
echo '{"pid":999999,"started":1,"file":"/tmp/gone.mp4","mode":"area"}' \
    > "${XDG_RUNTIME_DIR}/aquarius-capture/recording.json"
OUT="$(run status)"
case "${OUT}" in
    '{"recording":false,'*) pass "a dead recorder reads as 'not recording'" ;;
    *) fail "a dead recorder read as '${OUT}'" ;;
esac
if [ ! -e "${XDG_RUNTIME_DIR}/aquarius-capture/recording.json" ]; then
    pass "and the stale state file is cleared away"
else
    fail "the stale state file survived, so the next recording would be refused"
fi

# ==============================================================================
# 4. record — the state file's whole life
# ==============================================================================
echo "Recording: start, status, stop"
fresh_home record

STATE="${XDG_RUNTIME_DIR}/aquarius-capture/recording.json"

FILE="$(run record area)"
RC=$?
if [ "${RC}" -eq 0 ] && [ -n "${FILE}" ]; then
    pass "record area exits 0 once the recorder has really started"
else
    fail "record area exited ${RC} and printed '${FILE}'"
fi

NAME="$(basename "${FILE}")"
if [[ "${NAME}" =~ ^Screen\ Recording\ [0-9]{4}-[0-9]{2}-[0-9]{2}\ at\ [0-9]{2}\.[0-9]{2}\.[0-9]{2}\.mp4$ ]]; then
    pass "it is named '${NAME}' — Mac style"
else
    fail "the name '${NAME}' is not 'Screen Recording YYYY-MM-DD at HH.MM.SS.mp4'"
fi

if [ -s "${STATE}" ]; then
    pass "the state file exists where the bar looks for it"
else
    fail "no ${STATE} — the bar would never draw its red dot"
fi

# The four fields the bar reads, by name.
for field in pid started file mode; do
    if grep -q "\"${field}\"" "${STATE}"; then
        pass "the state file carries \"${field}\""
    else
        fail "the state file has no \"${field}\" — the bar reads it by name"
    fi
done
if grep -q '"mode":"area"' "${STATE}"; then
    pass "and the mode is recorded as the one that was asked for"
else
    fail "the mode in the state file is not 'area'"
fi

OUT="$(run status)"
case "${OUT}" in
    '{"recording":true,'*"${FILE}"*) pass "status now says true and names the file" ;;
    *) fail "status while recording said '${OUT}'" ;;
esac

# Starting a second recording on top of the first must be refused, not silently
# allowed — two recorders on one screen is two half files.
if run record area > /dev/null 2>&1; then
    fail "a second recording was allowed to start over the first"
else
    pass "a second recording is refused while one is running"
fi

# ⚠️ TIMED, AND THE TIMING IS THE POINT. Stopping must take a moment, not
# fifteen seconds. Two separate bugs found on 2026-09-13 both showed up here and
# nowhere else, because both left a recorder that ignored the polite interrupt
# and was killed by the fallback a quarter of a minute later:
#
#   1. `setsid cmd &` recording setsid's pid rather than the recorder's;
#   2. a shell starting background jobs with SIGINT IGNORED — which survives
#      exec, so the recorder inherited a deaf ear.
#
# Both produce a stop button that appears to hang and a file finished by force.
# If this check ever starts taking fifteen seconds again, that is what happened.
STOP_BEGAN="$(date +%s)"
STOPPED="$(run record stop)"
RC=$?
STOP_TOOK=$(($(date +%s) - STOP_BEGAN))
if [ "${STOP_TOOK}" -lt 5 ]; then
    pass "stopping took ${STOP_TOOK}s — the recorder heard the interrupt"
else
    fail "stopping took ${STOP_TOOK}s — the recorder ignored the interrupt and was killed by the fallback"
fi
if [ "${RC}" -eq 0 ] && [ "${STOPPED}" = "${FILE}" ]; then
    pass "record stop exits 0 and prints the same file back"
else
    fail "record stop exited ${RC} and printed '${STOPPED}' (expected '${FILE}')"
fi

# ⚠️ THE CHECK THAT PROVES IT STOPPED *CLEANLY*. The fake recorder appends END
# only when it is interrupted politely and given time to finish — exactly what
# the real wf-recorder needs in order to write the index that makes an MP4
# playable. Kill it outright and this line fails.
if grep -q 'END' "${FILE}"; then
    pass "the recorder was interrupted politely and finished its file"
else
    fail "the file has no ending — the recorder was killed rather than stopped"
fi

if [ ! -e "${STATE}" ]; then
    pass "the state file is gone after stopping"
else
    fail "the state file survived the stop — the bar would stay red forever"
fi

OUT="$(run status)"
case "${OUT}" in
    '{"recording":false,'*) pass "and status says false again" ;;
    *) fail "status after stopping said '${OUT}'" ;;
esac

# Stopping when nothing is running is a shrug, not an error: the bar may send it
# after a crash and it must not turn red.
if run record stop > /dev/null 2>&1; then
    pass "stopping when nothing is running is not an error"
else
    fail "record stop with nothing running exited non-zero"
fi

# A recorder that falls over at once (no such encoder, no permission on the
# graphics device) must be reported, not left as a red dot over nothing.
fresh_home record-dies
if FAKE_RECORDER_DIE=1 run record area > /dev/null 2>&1; then
    fail "a recorder that died immediately was reported as a success"
else
    pass "a recorder that dies immediately is reported as a failure"
fi
if [ ! -e "${XDG_RUNTIME_DIR}/aquarius-capture/recording.json" ]; then
    pass "and no state file is left claiming it is recording"
else
    fail "a state file was written for a recorder that never ran"
fi

# ==============================================================================
# 5. `setup` — the folder, user-dirs.dirs, and the Files pin
# ==============================================================================
echo "The once-per-person setup"
fresh_home setup

run setup

if [ -d "${HOME}/Screenshots" ]; then
    pass "setup makes the Screenshots folder"
else
    fail "setup did not make ${HOME}/Screenshots"
fi

if grep -q 'XDG_SCREENSHOTS_DIR' "${XDG_CONFIG_HOME}/user-dirs.dirs" 2> /dev/null; then
    pass "setup writes XDG_SCREENSHOTS_DIR, so GNOME's own tool saves here too"
else
    fail "setup did not write XDG_SCREENSHOTS_DIR into user-dirs.dirs"
fi

for v in 3 4; do
    B="${XDG_CONFIG_HOME}/gtk-${v}.0/bookmarks"
    if grep -Fq "file://${HOME}/Screenshots Screenshots" "${B}" 2> /dev/null; then
        pass "the folder is pinned in the Files sidebar (GTK ${v})"
    else
        fail "no pin in ${B}"
    fi
done

# ⚠️ RUNNING IT AGAIN MUST CHANGE NOTHING. It runs at EVERY login, so anything
# that appends unconditionally would grow a bookmarks file without limit and
# fill somebody's sidebar with copies of one folder.
B3="${XDG_CONFIG_HOME}/gtk-3.0/bookmarks"
BEFORE="$(cat "${B3}")"
run setup
run setup
if [ "$(cat "${B3}")" = "${BEFORE}" ]; then
    pass "running setup again adds nothing (it runs at every login)"
else
    fail "setup added the pin more than once"
fi
if [ "$(grep -c 'XDG_SCREENSHOTS_DIR' "${XDG_CONFIG_HOME}/user-dirs.dirs")" -eq 1 ]; then
    pass "and user-dirs.dirs still names the folder exactly once"
else
    fail "user-dirs.dirs grew a second XDG_SCREENSHOTS_DIR line"
fi

# ⚠️ AND THE RULE THAT MATTERS MOST: NEVER FIGHT THE PERSON. Somebody who drags
# the pin out of their sidebar must keep it out, forever. The marker file under
# ~/.local/state/aquarius is what makes that true.
MARKER="${XDG_STATE_HOME}/aquarius/capture-bookmark-done"
if [ -e "${MARKER}" ]; then
    pass "the 'we have offered the pin' marker is written"
else
    fail "no marker at ${MARKER} — the pin would be re-added forever"
fi

# grep -v exits 1 when it selects no lines, so the mv must not hang off &&.
grep -v 'Screenshots' "${B3}" > "${B3}.tmp" || true
mv "${B3}.tmp" "${B3}"
run setup
if grep -Fq "Screenshots" "${B3}" 2> /dev/null; then
    fail "a pin the person REMOVED was put back — the machine is fighting them"
else
    pass "a pin the person removed stays removed"
fi

# Deleting the marker is the documented way to be offered it once more.
rm -f "${MARKER}"
run setup
if grep -Fq "file://${HOME}/Screenshots Screenshots" "${B3}"; then
    pass "deleting the marker offers the pin once more, as documented"
else
    fail "deleting the marker did not offer the pin again"
fi

# A bookmarks file with no newline at the end must not have our line glued onto
# somebody else's.
fresh_home setup-nonewline
mkdir -p "${XDG_CONFIG_HOME}/gtk-3.0"
printf 'file:///somewhere Somewhere' > "${XDG_CONFIG_HOME}/gtk-3.0/bookmarks"
run setup
if grep -Fxq "file:///somewhere Somewhere" "${XDG_CONFIG_HOME}/gtk-3.0/bookmarks"; then
    pass "an existing bookmark with no trailing newline is left intact"
else
    fail "our line was glued onto an existing bookmark"
fi

# ==============================================================================
# 6. The things a wrong word should do
# ==============================================================================
echo "Being asked for something that does not exist"
fresh_home nonsense
if run wibble > /dev/null 2>&1; then
    fail "an unknown command was accepted"
else
    pass "an unknown command is refused with a non-zero exit"
fi
if run --help | grep -q 'aquarius-capture shot screen'; then
    pass "--help prints the commands"
else
    fail "--help does not list the commands"
fi

# ==============================================================================
# 7. The guide (only when run from the repository; the image has no docs/)
# ==============================================================================
DOCS="${HERE}/../docs/restart"
if [ -d "${DOCS}" ]; then
    echo "The plain-English guide"
    if [ -s "${DOCS}/screenshots.md" ]; then
        pass "docs/restart/screenshots.md exists"
    else
        fail "docs/restart/screenshots.md is missing — the feature ships with no explanation"
    fi
    if grep -q 'screenshots\.md' "${DOCS}/README.md" 2> /dev/null; then
        pass "and the docs index lists it"
    else
        fail "docs/restart/README.md does not list screenshots.md"
    fi
fi

# ==============================================================================
echo
if [ "${FAILED}" -eq 0 ]; then
    echo "test-capture: ${PASSED} checks passed."
    exit 0
fi
echo "test-capture: ${FAILED} of $((PASSED + FAILED)) checks FAILED."
exit 1
