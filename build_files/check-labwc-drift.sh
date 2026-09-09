#!/usr/bin/env bash
# ==============================================================================
# CHANGE ONE, CHANGE BOTH — the labwc drift check
# ==============================================================================
# WHAT THIS IS FOR, IN ONE PARAGRAPH
#
# The Aquarius Desktop's window manager, labwc, is configured by a folder that
# exists TWICE: once in the aquarius-shell repository, under session/labwc/, and
# once here, under system_files/usr/share/aquarius/labwc/.
# The copy here is the one that ships on a real machine. The copy over there is
# the one that runs when somebody starts the session from a clone of the shell.
# There is no build step that copies one onto the other — on purpose, because
# our copies carry OS-only corrections — so the two are kept in step BY HAND.
#
# Twice in one day that failed:
#
#   6 September 2026, morning    the shell had grown a menu.xml and a
#                                right-click binding; this image had neither, so
#                                right-clicking the desktop showed labwc's own
#                                built-in menu (Terminal / Reconfigure / Exit).
#   6 September 2026, afternoon  the shell had grown Super+Tab and
#                                Super+Shift+Tab; this image had neither, so
#                                Command+Tab in Mac mode did nothing on our
#                                desktop while working perfectly in GNOME.
#
# Both times the fix was to copy the missing thing across, and both times the
# build was then taught to look for that ONE thing by name. That does not scale
# and it does not generalise: the next thing the shell adds will be a thing
# nobody has written a check for yet. So this script compares the two copies
# DIRECTLY and fails on any difference in content, whatever that difference
# turns out to be.
#
# ------------------------------------------------------------------------------
# HOW TO RUN IT BY HAND
# ------------------------------------------------------------------------------
#     git clone https://github.com/stoneharborent/aquarius-shell.git /tmp/shell
#     cd /tmp/shell && git checkout --detach <the commit in aquarius-os.env>
#     cd - && ./build_files/check-labwc-drift.sh /tmp/shell
#
# It reads files and prints. It changes nothing, needs no root, and needs no
# container. CI runs this exact script — see the shell_tests job in
# .github/workflows/build.yml — so a green run here means a green run there.
#
# ------------------------------------------------------------------------------
# WHAT "THE SAME" MEANS, FILE BY FILE
# ------------------------------------------------------------------------------
# The two copies are deliberately NOT byte-identical: each carries its own prose
# comments, written for its own reader. Comments are therefore never compared.
# What is compared is what the program actually acts on.
#
#   rc.xml             Every element, attribute and value, comments excluded.
#                      The files are parsed as XML and reduced to a plain,
#                      indented listing — one line per element, attributes in
#                      alphabetical order — so that a difference in indentation,
#                      in attribute order, or in how a comment is worded cannot
#                      show up as drift, and a difference in an actual setting
#                      always does.
#
#   menu.xml           The same treatment. Note that this includes the
#                      `env XDG_CURRENT_DESKTOP=GNOME` prefix on the Settings
#                      commands: the shell's copy carries it too, as of
#                      db672bb, so the two really are content-identical and this
#                      check can be strict about it.
#
#   generate-theme     ⚠️ NOT COMPARED AS TEXT. THE OUTPUT IS COMPARED INSTEAD.
#
#                      Since 2026-09-06 labwc's colours are not written by hand
#                      in either repository. There was a file called
#                      themerc-override holding a second copy of the shell's Ice
#                      palette, and it is gone; generate-theme reads the shell's
#                      theme/Ice.qml or theme/Midnight.qml and writes the file
#                      out instead.
#
#                      Comparing two PROGRAMS line by line would be a weak
#                      check: two generators can be written differently and
#                      still agree, or be written identically and disagree
#                      because one of them reads a palette the other does not
#                      have. So this script RUNS BOTH — the shell's copy against
#                      the shell's palette, ours against the same palette — for
#                      both themes at two sizes, and compares what comes out.
#                      That is the thing that actually reaches a screen.
#
#   autostart          THE ONE THAT IS NOT A STRAIGHT COMPARISON, and the reason
#                      is worth reading before changing anything here.
#
#                      The OS copy of autostart is deliberately the LARGER file.
#                      It starts things that only exist on an installed
#                      AquariusOS machine — the wallpaper, the display-scale
#                      helper, the polkit agent, the portal reset, the
#                      shell-start wrapper that puts a dialog on screen when the
#                      shell dies. The shell repository has no business knowing
#                      about any of those, and its copy just runs `qs`.
#
#                      So "identical" would be the wrong rule and would fail on
#                      a perfectly correct pair of files. The rule that IS right
#                      is one-directional: EVERY LINE THAT RUNS IN THE SHELL'S
#                      COPY MUST ALSO RUN IN OURS. That is the direction the
#                      damage travels — the shell gains a login-time step, ours
#                      does not get it, and a machine quietly stops doing
#                      something. Extra lines on our side are expected and are
#                      not drift.
#
#                      ⚠️ A WORKED EXAMPLE, ADDED 8 SEPTEMBER 2026, BECAUSE
#                      SOMEBODY WILL READ THE RULE AND WONDER IF IT IS REALLY
#                      MEANT. Our copy now runs
#
#                          /usr/libexec/aquarius-wallpaper auto
#
#                      at login, and the shell's copy runs nothing of the kind.
#                      That is not drift and this script says nothing about it.
#                      The program lives in /usr/libexec on a real machine, and
#                      the shell repository — which is meant to run from a clone
#                      on somebody's plain Fedora box — cannot assume it exists.
#                      Nothing was LOST from the shell's copy, which is the only
#                      direction this check looks in, so an OS-only line like
#                      this one is expected and allowed.
#
#                      (The line it replaced ran `swaybg` from this file by hand,
#                      naming the Ice picture, and never ran again — which is the
#                      whole reason a dark desktop kept a pale wallpaper. That it
#                      does not come back is checked in the IMAGE build, by
#                      build_files/55-aquarius-session.sh, not here: it is a fact
#                      about our copy alone and the shell has no opinion on it.)
#
#                      Three lines are the known, deliberate exceptions, listed
#                      in AQ_AUTOSTART_KNOWN_DIFFERENT below with a sentence
#                      each. Anything else is a failure.
#
# ------------------------------------------------------------------------------
# WHY THIS SCRIPT IS NOT INSIDE THE IMAGE BUILD
# ------------------------------------------------------------------------------
# It compares this repository against ANOTHER repository, and the image build
# has only this one. The build's own checks (build_files/55-aquarius-session.sh)
# read the installed files and ask whether each is well-formed and complete;
# this asks the different question of whether it agrees with the shell. Both are
# needed and neither replaces the other.
# ------------------------------------------------------------------------------
# WHY THE SHEBANG SAYS `env bash` WHEN EVERY OTHER FILE IN build_files/ SAYS
# /usr/bin/bash
# ------------------------------------------------------------------------------
# The other scripts here run INSIDE the image being built, on Fedora, where bash
# is always at /usr/bin/bash. This one never runs in the image: it runs on a
# GitHub runner and on whatever laptop somebody is sitting at, and on a Mac bash
# is at /bin/bash. `env bash` finds it wherever it is. That is the same shebang
# every script in tests/ uses, and for the same reason.
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# Where the two copies live
# ------------------------------------------------------------------------------
# The repository root is worked out from where this script is, not from where
# somebody happened to be standing when they ran it.
AQ_HERE="$(cd "$(dirname "$0")" && pwd)"
AQ_REPO_ROOT="$(cd "${AQ_HERE}/.." && pwd)"
AQ_OS_DIR="${AQ_REPO_ROOT}/system_files/usr/share/aquarius/labwc"

if [ "$#" -ne 1 ]; then
    echo "usage: $(basename "$0") <a-clone-of-aquarius-shell>" >&2
    echo "" >&2
    echo "Compares this repository's copies of the labwc configuration files" >&2
    echo "against the aquarius-shell repository's copies of the same files." >&2
    exit 2
fi

AQ_SHELL_CLONE="$1"
AQ_SHELL_DIR="${AQ_SHELL_CLONE}/session/labwc"

if [ ! -d "${AQ_SHELL_DIR}" ]; then
    echo "ERROR: ${AQ_SHELL_DIR} does not exist." >&2
    echo "The argument should be the top of a clone of aquarius-shell — the" >&2
    echo "folder that has session/labwc/ inside it." >&2
    exit 2
fi

if [ ! -d "${AQ_OS_DIR}" ]; then
    echo "ERROR: ${AQ_OS_DIR} does not exist." >&2
    echo "This script has to be run from inside a clone of the aquarius-os" >&2
    echo "repository — it lives in build_files/ and finds the rest from there." >&2
    exit 2
fi

# ------------------------------------------------------------------------------
# Which commit of the shell is being compared against
# ------------------------------------------------------------------------------
# aquarius-os.env is the one place the pinned commit is written down, so it is
# read from there rather than typed in twice. If the clone is sitting on a
# DIFFERENT commit then the answer this script gives is about some other version
# of the shell, which is worse than no answer at all — so that stops it.
AQ_PIN="$(grep -E '^AQUARIUS_SHELL_REF=' "${AQ_REPO_ROOT}/aquarius-os.env" | cut -d'"' -f2 || true)"
if [ -z "${AQ_PIN}" ]; then
    echo "ERROR: aquarius-os.env does not say which commit of the shell this image ships." >&2
    exit 2
fi

AQ_CLONE_HEAD=""
if [ -d "${AQ_SHELL_CLONE}/.git" ]; then
    AQ_CLONE_HEAD="$(git -C "${AQ_SHELL_CLONE}" rev-parse HEAD 2> /dev/null || true)"
fi

echo "=============================================================================="
echo " Do the two copies of the labwc files still agree?"
echo "=============================================================================="
echo "  the image's copies : ${AQ_OS_DIR}"
echo "  the shell's copies : ${AQ_SHELL_DIR}"
echo "  the pinned commit  : ${AQ_PIN}"
if [ -n "${AQ_CLONE_HEAD}" ]; then
    echo "  the clone is at    : ${AQ_CLONE_HEAD}"
    if [ "${AQ_CLONE_HEAD}" != "${AQ_PIN}" ]; then
        echo ""
        echo "ERROR: that clone is not the commit this image ships."
        echo "AQUARIUS_SHELL_REF in aquarius-os.env says ${AQ_PIN}."
        echo "Check the clone out at that commit and run this again:"
        echo "    git -C ${AQ_SHELL_CLONE} checkout --detach ${AQ_PIN}"
        exit 2
    fi
else
    echo "  the clone is at    : (not a git checkout — cannot confirm it is the pinned commit)"
fi
echo ""

# ------------------------------------------------------------------------------
# The three lines autostart is allowed to differ on
# ------------------------------------------------------------------------------
# Each of these runs in the SHELL's copy and deliberately does not run in ours,
# because ours does the same job a different way. Adding to this list is a real
# decision and wants a sentence saying why — an entry here switches off the only
# thing that would notice that line going missing from the image.
AQ_AUTOSTART_KNOWN_DIFFERENT=(
    # The shell pushes its WHOLE environment to systemd and D-Bus. Ours pushes
    # the two variables that did not exist before labwc started, because the
    # launcher (/usr/bin/aquarius-session) has already pushed the rest of the
    # list, from AQ_SESSION_ENV_PUSH, and that same list is what logout removes
    # again. Pushing everything here would put variables into systemd that
    # logout does not know to take out.
    'dbus-update-activation-environment --systemd --all 2>/dev/null || true'
    # The fallback for a machine without dbus-update-activation-environment,
    # same difference and same reason.
    'systemctl --user import-environment 2>/dev/null || true'
    # The shell's copy starts Quickshell directly. Ours goes through
    # /usr/libexec/aquarius-shell-start, which does the same thing and then puts
    # a dialog on screen if the shell fails, so that a broken shell is a message
    # rather than an empty desktop. That helper only exists in the image.
    # (Written with the dollar signs escaped so the shell stores the line as
    # text. It is a line to LOOK FOR, never a line to run.)
    "qs 2>&1 | sed -u 's/^/[shell] /' >> \"\${AQ_LOG:-/dev/null}\" &"
)

# ------------------------------------------------------------------------------
# aq_xml_content <file>
# ------------------------------------------------------------------------------
# Reduces an XML file to just its content: one line per element, indented by
# depth, with attributes in alphabetical order and any text value after an
# `=`. Comments are gone, because Python's XML parser does not report them;
# indentation and line breaks are gone, because the listing rebuilds its own.
# Two files that produce the same listing are the same configuration.
aq_xml_content() {
    python3 - "$1" <<'PY'
import sys
import xml.etree.ElementTree as ET


def walk(element, depth, lines):
    attributes = " ".join(
        '%s="%s"' % (name, value) for name, value in sorted(element.attrib.items())
    )
    line = ("  " * depth) + element.tag
    if attributes:
        line += " " + attributes
    text = " ".join((element.text or "").split())
    if text:
        line += " = " + text
    lines.append(line)
    for child in element:
        walk(child, depth + 1, lines)
    # Text AFTER a child's closing tag is content too. It is always whitespace
    # in these files, but reporting it rather than dropping it means this
    # listing can never quietly lose something.
    tail = " ".join((element.tail or "").split())
    if tail:
        lines.append(("  " * depth) + "(text after </%s>) = %s" % (element.tag, tail))


try:
    root = ET.parse(sys.argv[1]).getroot()
except ET.ParseError as problem:
    sys.stderr.write("%s is not well-formed XML: %s\n" % (sys.argv[1], problem))
    sys.exit(1)

collected = []
walk(root, 0, collected)
print("\n".join(collected))
PY
}

# ------------------------------------------------------------------------------
# aq_plain_content <file>
# ------------------------------------------------------------------------------
# Every line that is not blank and not a comment, trimmed of the spaces at both
# ends. This is the right reduction for both of the non-XML files: labwc's
# themerc has no end-of-line comment syntax, and in a shell script the
# indentation is for people.
aq_plain_content() {
    sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$1" \
        | grep -v '^#' \
        | grep -v '^$' \
        || true
}

AQ_TMP="$(mktemp -d)"
trap 'rm -rf "${AQ_TMP}"' EXIT

AQ_FAILS=0

# ------------------------------------------------------------------------------
# aq_report_drift <file> <extra explanation>
# ------------------------------------------------------------------------------
# One failure message, said the same way every time, so that whoever reads the
# build log knows immediately what happened and what to do about it.
aq_report_drift() {
    AQ_FAILS=1
    echo ""
    echo "  FAIL  $1"
    echo ""
    echo "  The shell's copy at ${AQ_PIN} and the OS copy differ — CHANGE ONE, CHANGE BOTH."
    echo ""
    echo "  $2"
    echo ""
    echo "  The two files are:"
    echo "    the image's : system_files/usr/share/aquarius/labwc/$1"
    echo "    the shell's : session/labwc/$1  (aquarius-shell @ ${AQ_PIN})"
    echo ""
    echo "  Nothing copies one onto the other. AquariusOS keeps its own"
    echo "  hand-maintained copies of these files, so a change made in one"
    echo "  repository has to be made in the other by hand. Bringing the image's"
    echo "  copy up to date is usually the answer; if the difference is"
    echo "  deliberate and OS-only, say so where this script explains that file."
    echo ""
    echo "  What differs (- is the image's copy, + is the shell's):"
    echo "  ----------------------------------------------------------------------"
}

# ------------------------------------------------------------------------------
# Both files have to exist before anything can be compared
# ------------------------------------------------------------------------------
for aq_f in rc.xml menu.xml generate-theme autostart; do
    if [ ! -s "${AQ_OS_DIR}/${aq_f}" ]; then
        echo "  FAIL  ${AQ_OS_DIR}/${aq_f} is missing or empty."
        echo "        The shell has session/labwc/${aq_f}; this image must ship its own copy."
        AQ_FAILS=1
    fi
    if [ ! -s "${AQ_SHELL_DIR}/${aq_f}" ]; then
        echo "  FAIL  ${AQ_SHELL_DIR}/${aq_f} is missing or empty."
        echo "        Either the shell dropped the file, or the pin is wrong."
        AQ_FAILS=1
    fi
done
if [ "${AQ_FAILS}" -ne 0 ]; then
    echo ""
    echo "Cannot compare files that are not there. Stopping."
    exit 1
fi

# ------------------------------------------------------------------------------
# rc.xml and menu.xml — every element and attribute, comments excluded
# ------------------------------------------------------------------------------
for aq_f in rc.xml menu.xml; do
    if ! aq_xml_content "${AQ_OS_DIR}/${aq_f}" > "${AQ_TMP}/os-${aq_f}.txt"; then
        echo "  FAIL  the image's ${aq_f} could not be parsed as XML (see above)."
        AQ_FAILS=1
        continue
    fi
    if ! aq_xml_content "${AQ_SHELL_DIR}/${aq_f}" > "${AQ_TMP}/shell-${aq_f}.txt"; then
        echo "  FAIL  the shell's ${aq_f} could not be parsed as XML (see above)."
        AQ_FAILS=1
        continue
    fi

    if diff -q "${AQ_TMP}/os-${aq_f}.txt" "${AQ_TMP}/shell-${aq_f}.txt" > /dev/null; then
        echo "  OK    ${aq_f} — every element and attribute matches (comments excluded)"
    else
        aq_report_drift "${aq_f}" \
            "The two files describe different configurations. Only the prose is allowed to differ."
        diff -u "${AQ_TMP}/os-${aq_f}.txt" "${AQ_TMP}/shell-${aq_f}.txt" \
            | tail -n +3 | sed 's/^/  /' || true
        echo "  ----------------------------------------------------------------------"
    fi
done

# ------------------------------------------------------------------------------
# generate-theme — RUN BOTH COPIES AND COMPARE WHAT THEY PRODUCE
# ------------------------------------------------------------------------------
# Read the note at the top of this file for why this one is not a text
# comparison. In short: two programs can be written differently and still agree,
# and the thing that reaches a screen is what they WRITE, not how they are
# written. So both copies are run — against the same shell palette, for both
# themes and at two sizes — and their output is compared line for line, with
# comments dropped the way the rest of this script drops them.
#
# The four combinations are Ice and Midnight (a colour role in one palette and
# not the other breaks the desktop the moment somebody flips the theme) at 1x
# and 1.25x (1.25 is the size Royce approved on the bench on 2026-09-03).
#
# ⚠️ BOTH RUNS READ THE SHELL'S PALETTE, and that is the point rather than a
# shortcut. This image does not carry theme/Ice.qml — it fetches the whole shell
# at the pinned commit at build time — so "the palette" is the shell's, once,
# and what is being asked here is whether the two GENERATORS agree about what to
# do with it.

if ! command -v python3 > /dev/null 2>&1; then
    echo "  SKIP  generate-theme — python3 is not on this machine."
    echo "        CI has it; see the shell_tests job in .github/workflows/build.yml."
else
    AQ_GEN_OK=1
    for aq_case in "ice 1" "ice 1.25" "midnight 1" "midnight 1.25"; do
        # shellcheck disable=SC2086
        set -- ${aq_case}
        aq_scheme="$1"
        aq_gen_scale="$2"
        aq_label="${aq_scheme} at ${aq_gen_scale}x"

        for aq_side in os shell; do
            if [ "${aq_side}" = "os" ]; then
                aq_gen="${AQ_OS_DIR}/generate-theme"
                aq_tmpl="${AQ_OS_DIR}"
            else
                aq_gen="${AQ_SHELL_DIR}/generate-theme"
                aq_tmpl="${AQ_SHELL_DIR}"
            fi

            if ! python3 "${aq_gen}" --quiet \
                    --scheme "${aq_scheme}" --scale "${aq_gen_scale}" \
                    --buttons mac \
                    --palette-dir "${AQ_SHELL_CLONE}/theme" \
                    --template-dir "${aq_tmpl}" \
                    --config-out "${AQ_TMP}/${aq_side}/${aq_scheme}-${aq_gen_scale}/config" \
                    --theme-out "${AQ_TMP}/${aq_side}/${aq_scheme}-${aq_gen_scale}/theme" \
                    --gtk-out "${AQ_TMP}/${aq_side}/${aq_scheme}-${aq_gen_scale}/gtk" \
                    2> "${AQ_TMP}/${aq_side}-${aq_scheme}-${aq_gen_scale}.err"; then
                echo ""
                echo "  FAIL  the ${aq_side} copy of generate-theme failed for ${aq_label}:"
                sed 's/^/        /' "${AQ_TMP}/${aq_side}-${aq_scheme}-${aq_gen_scale}.err" || true
                AQ_FAILS=1
                AQ_GEN_OK=0
            fi
        done

        [ "${AQ_GEN_OK}" -eq 1 ] || continue

        aq_os_dir="${AQ_TMP}/os/${aq_scheme}-${aq_gen_scale}"
        aq_sh_dir="${AQ_TMP}/shell/${aq_scheme}-${aq_gen_scale}"

        # The themerc: every setting line, comments dropped.
        aq_plain_content "${aq_os_dir}/config/themerc-override" \
            > "${AQ_TMP}/os-themerc.txt"
        aq_plain_content "${aq_sh_dir}/config/themerc-override" \
            > "${AQ_TMP}/shell-themerc.txt"

        if diff -q "${AQ_TMP}/os-themerc.txt" "${AQ_TMP}/shell-themerc.txt" \
                > /dev/null; then
            echo "  OK    the generated themerc for ${aq_label} matches"
        else
            aq_report_drift "generate-theme" \
                "The two generators disagree about the ${aq_label} theme, so the desktop menu and the window title bars would be drawn differently on an installed machine than on a clone of the shell."
            diff -u "${AQ_TMP}/os-themerc.txt" "${AQ_TMP}/shell-themerc.txt" \
                | tail -n +3 | sed 's/^/  /' || true
            echo "  ----------------------------------------------------------------------"
        fi

        # The button pictures: same names, same contents. These are XML, but
        # they are GENERATED XML with no prose in them, so a byte comparison is
        # the right one and it is stricter.
        if diff -r "${aq_os_dir}/theme" "${aq_sh_dir}/theme" > "${AQ_TMP}/buttons.diff" 2>&1; then
            echo "  OK    the window button pictures for ${aq_label} match"
        else
            aq_report_drift "generate-theme" \
                "The two generators drew different window buttons for ${aq_label}."
            sed 's/^/  /' "${AQ_TMP}/buttons.diff" | head -n 40 || true
            echo "  ----------------------------------------------------------------------"
        fi
    done
fi

# ------------------------------------------------------------------------------
# autostart — every line that RUNS in the shell's copy must also run in ours
# ------------------------------------------------------------------------------
# Read the long note at the top of this file for why this one is not a straight
# comparison. In short: our copy is deliberately the bigger of the two, so extra
# lines on our side are expected, and only a line MISSING from our side is drift.
aq_plain_content "${AQ_OS_DIR}/autostart" > "${AQ_TMP}/os-autostart.txt"
aq_plain_content "${AQ_SHELL_DIR}/autostart" > "${AQ_TMP}/shell-autostart.txt"

: > "${AQ_TMP}/autostart-missing.txt"
while IFS= read -r aq_line; do
    [ -n "${aq_line}" ] || continue

    aq_known=0
    for aq_allowed in "${AQ_AUTOSTART_KNOWN_DIFFERENT[@]}"; do
        if [ "${aq_line}" = "${aq_allowed}" ]; then
            aq_known=1
            break
        fi
    done
    [ "${aq_known}" -eq 1 ] && continue

    # --fixed-strings, and the whole line: these are shell lines full of $, *,
    # quotes and pipes, and reading any of them as a pattern would give an
    # answer about something else entirely.
    if ! grep -qxF -- "${aq_line}" "${AQ_TMP}/os-autostart.txt"; then
        printf '%s\n' "${aq_line}" >> "${AQ_TMP}/autostart-missing.txt"
    fi
done < "${AQ_TMP}/shell-autostart.txt"

if [ ! -s "${AQ_TMP}/autostart-missing.txt" ]; then
    echo "  OK    autostart — every line that runs in the shell's copy also runs in ours"
else
    aq_report_drift "autostart" \
        "The shell's autostart runs something at login that the image's autostart does not, so an installed machine would silently skip it."
    while IFS= read -r aq_line; do
        printf '  + %s\n' "${aq_line}"
    done < "${AQ_TMP}/autostart-missing.txt"
    echo "  ----------------------------------------------------------------------"
    echo "  (Lines the IMAGE has and the shell does not are fine and are not"
    echo "  listed: our copy is deliberately the larger of the two.)"
fi

echo ""
if [ "${AQ_FAILS}" -ne 0 ]; then
    echo "=============================================================================="
    echo " The two copies of the labwc files have drifted apart."
    echo "=============================================================================="
    echo "This is the fault that cost two bench sessions on 6 September 2026. Fix it by"
    echo "making the same change in both repositories, then run this again."
    exit 1
fi

echo "=============================================================================="
echo " The labwc files, and what generate-theme makes of them, agree with the"
echo " shell at ${AQ_PIN}."
echo "=============================================================================="
