#!/usr/bin/bash
# ==============================================================================
# Shared helpers for the AquariusOS build scripts
# ==============================================================================
# Every numbered script in this folder starts by reading this file. It exists so
# that all of them fail the same way, log the same way, and check their work the
# same way — and so that "did that actually happen?" is one word instead of five
# lines copied around.
#
# Nothing here is clever. It is a heading printer, a failure counter, and two
# words for pass and fail.
#
# THE ONE RULE THIS FILE ENCODES
#
#   Trust content, never timestamps.
#
# We learned this the hard way on 2026-08-31: a build step checked whether a
# file was NEWER than another to decide whether it had done its job. That works
# on a normal computer and is meaningless here, because the tool that packages a
# bootable image flattens every file's clock to the same value. The check passed
# forever, including when the step had silently done nothing.
#
# So every check in this repo reads the actual contents — the text in the file,
# the value the setting reports, the answer `rpm -q` gives. Never a date.
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# say "..."  — a heading in the build log
# ------------------------------------------------------------------------------
# GitHub Actions build logs are thousands of lines long. These headings are how
# a person finds the part that went wrong.
say() {
    echo
    echo "=== $* ==="
}

# ------------------------------------------------------------------------------
# The check counter
# ------------------------------------------------------------------------------
# ok "..."   record that something is as it should be
# bad "..."  record that it is not, and remember to fail at the end
#
# Why not just exit on the first problem: because then you fix one thing, wait
# fifteen minutes for another build, and find the next one. Collecting them
# means one build tells you everything that is wrong.
AQ_FAILS=0
ok() { echo "  OK   $*"; }
bad() {
    echo "  FAIL $*" >&2
    AQ_FAILS=$((AQ_FAILS + 1))
}

# ------------------------------------------------------------------------------
# aq_finish "<what this step was>"
# ------------------------------------------------------------------------------
# Call this at the end of a script. If anything called bad(), the build stops
# here with a message GitHub shows in red at the top of the run.
aq_finish() {
    if [ "${AQ_FAILS}" -ne 0 ]; then
        echo "::error::${1}: ${AQ_FAILS} check(s) failed. Scroll up for the FAIL lines."
        exit 1
    fi
    say "${1}: all checks passed."
}

# ------------------------------------------------------------------------------
# aq_have <command>  — is this program in the image?
# ------------------------------------------------------------------------------
aq_have() { command -v "$1" > /dev/null 2>&1; }

# ------------------------------------------------------------------------------
# aq_installed <package> [<package>...]  — are these packages really installed?
# ------------------------------------------------------------------------------
# `dnf install` can succeed having installed something slightly different from
# what you asked for (a package that "provides" the name you typed). This asks
# the package database directly, which is the answer that matters.
aq_installed() {
    local pkg
    for pkg in "$@"; do
        if rpm -q "${pkg}" > /dev/null 2>&1; then
            ok "${pkg} $(rpm -q --queryformat '%{VERSION}-%{RELEASE}' "${pkg}")"
        else
            bad "${pkg} is NOT installed"
        fi
    done
}

# ------------------------------------------------------------------------------
# aq_file_has <file> <pattern> "<description>"
# ------------------------------------------------------------------------------
# Reads a file and checks its contents match. Contents, not clocks.
aq_file_has() {
    if [ ! -r "$1" ]; then
        bad "$3 — ${1} does not exist"
        return
    fi
    if grep -Eq "$2" "$1"; then
        ok "$3"
    else
        bad "$3 — /$2/ not found in $1"
    fi
}

# ------------------------------------------------------------------------------
# aq_output_has <pattern> <command> [arguments...]
# ------------------------------------------------------------------------------
# "Does this command's output mention this?"
#
# ⚠️ THE REASON THIS EXISTS IS A TRAP THAT COST US THE FIRST BUILD OF THE
# RESTART (2026-09-03), AND IT LOOKS LIKE NOTHING.
#
# The obvious way to write this is:
#
#     if fc-list | grep -qi "Inter"; then
#
# and it is wrong in a script that uses `set -o pipefail`, which every script in
# this folder does. Here is what actually happens:
#
#   1. grep finds the match and exits IMMEDIATELY, because that is what -q means.
#   2. fc-list is still writing, discovers nobody is reading, and is killed by
#      the operating system with a "broken pipe" signal.
#   3. `pipefail` says "report the whole pipeline as failed if ANY part of it
#      failed" — and fc-list did fail, in step 2.
#   4. So the `if` takes the ELSE branch. Finding the thing you were looking for
#      makes the check report that it is missing.
#
# On the first restart build this reported that Inter, JetBrains Mono and Sora
# were all missing from an image that contained all three.
#
# This helper runs the command to completion, keeps its output, and then greps
# that. No pipe, no signal, no lie.
aq_output_has() { # aq_output_has <pattern> <command> [args...]
    local pattern="$1"
    shift
    local tmp
    tmp="$(mktemp)"
    "$@" > "${tmp}" 2> /dev/null || true
    if grep -qi -- "${pattern}" "${tmp}"; then
        rm -f "${tmp}"
        return 0
    fi
    rm -f "${tmp}"
    return 1
}

# ------------------------------------------------------------------------------
# aq_unit_is_on_from_usr <unit> "<what it does>"
# ------------------------------------------------------------------------------
# "Is this service switched on, in a way an update cannot lose?"
#
# ⚠️ WHY THIS IS NOT `systemctl enable`, AND WHY IT MATTERS ON THIS KIND OF
# OPERATING SYSTEM. Read this before changing how any AquariusOS unit is
# switched on.
#
# `systemctl enable foo.service` writes a symlink into /etc:
#
#     /etc/systemd/system/graphical.target.wants/foo.service
#
# On an ordinary Linux machine that is exactly right. On AquariusOS it is a
# trap, because /etc is not ours. Every update takes the /etc from the new image
# and MERGES the current machine's /etc onto it: anything the person changed
# locally wins, forever. That includes DELETIONS. So:
#
#   * somebody runs `sudo systemctl disable aquarius-gdm-display` once, in 2026,
#     to try something;
#   * that deletes the /etc symlink, which the merge records as "this machine
#     does not want that file";
#   * every update from then on carefully preserves the absence. The service is
#     off on that one machine, forever, and no image can switch it back on. It
#     looks exactly like a bug in the image.
#
# Royce hit this on the bench. So AquariusOS switches its own services on the
# other way: the symlink is SHIPPED IN THE IMAGE, under /usr, which is replaced
# whole at every update and which nothing local can edit:
#
#     /usr/lib/systemd/system/graphical.target.wants/foo.service
#
# systemd reads .wants folders from every unit directory, /usr included, so this
# starts the service exactly the same way. The difference is that an update
# always restores it and no local change can silently lose it.
#
# THE HONEST COST, which belongs in the docs of anything switched on this way:
# `systemctl disable` no longer turns it off, because there is nothing in /etc
# to remove. `sudo systemctl mask <unit>` does — that writes to /etc and beats
# everything — and each of our units has its own plain-English off switch
# (`aq login scale off`, and so on) which is the one to reach for first.
#
# This helper checks the shipped link CONTENTS, in the finished image. It also
# prints what `systemctl is-enabled` thinks, as information — that command's
# answer for a /usr-shipped link differs between systemd versions, so it is
# never what a build passes or fails on.
aq_unit_is_on_from_usr() {
    local unit="$1" what="${2:-}"
    local link="/usr/lib/systemd/system/graphical.target.wants/${unit}"

    if [ ! -L "${link}" ]; then
        bad "${link} is missing — ${unit} would be installed but never start"
        return
    fi
    echo "  ${link} -> $(readlink "${link}")"
    if [ -e "${link}" ]; then
        ok "${unit} is switched on from /usr, so an update always restores it${what:+ (${what})}"
    else
        bad "the 'switched on' link for ${unit} is dangling — it points at nothing"
    fi

    # ⚠️ NOTHING OF OURS MAY BE SWITCHED ON THROUGH /etc. If a `systemctl enable`
    # ever creeps back into a build script, this is what catches it — a machine
    # would then have the same unit wanted from two places and a `disable` that
    # half-works.
    if [ -e "/etc/systemd/system/graphical.target.wants/${unit}" ]; then
        bad "${unit} is ALSO switched on through /etc — a build step ran 'systemctl enable'. See the note in aq-lib.sh."
    else
        ok "nothing switches ${unit} on through /etc (an update could lose that)"
    fi

    if aq_have systemctl; then
        echo "  (for information) systemctl is-enabled ${unit}: $(systemctl is-enabled "${unit}" 2> /dev/null || echo "no answer")"
    fi
}

# ------------------------------------------------------------------------------
# aq_dnf <arguments...>  — install things
# ------------------------------------------------------------------------------
# On Fedora 44 the `dnf` command IS dnf5, but some images also ship it under the
# name `dnf5`. This picks whichever exists so the scripts do not care.
# The `|| echo dnf` at the end is not laziness: with `set -e`, an assignment
# whose command substitution exits non-zero kills the script on the spot, and
# `command -v` exits non-zero when it finds nothing. Falling back to the plain
# name means a machine without either one fails later, at the point of use,
# with a message about dnf — rather than here, silently, with no output at all.
AQ_DNF="$(command -v dnf5 2> /dev/null || command -v dnf 2> /dev/null || echo dnf)"
aq_dnf() {
    "${AQ_DNF}" -y "$@"
}
