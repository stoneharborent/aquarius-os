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
# aq_dnf <arguments...>  — install things
# ------------------------------------------------------------------------------
# On Fedora 44 the `dnf` command IS dnf5, but some images also ship it under the
# name `dnf5`. This picks whichever exists so the scripts do not care.
AQ_DNF="$(command -v dnf5 || command -v dnf)"
aq_dnf() {
    "${AQ_DNF}" -y "$@"
}
