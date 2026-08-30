#!/usr/bin/env bash
# ==============================================================================
# Tests for "is the login screen too big on this machine, and did we fix it?"
# ==============================================================================
# The script under test is
#   system_files/usr/libexec/aquarius-greeter-scale
#
# It answers one question and then does one thing, and both halves can go wrong
# in a way nobody would notice:
#
#   THE QUESTION  "does this machine need its login screen left at 100%?"
#     Answer yes too often and every desktop PC in the world gets its login
#     screen quietly rewritten by us, which is exactly the sort of thing this
#     project promises never to do.
#     Answer no too often and Royce's Ally still cannot see its own login box.
#
#   THE DOING     "put our file in the login screen's home folder"
#     The one that matters here is that it OVERWRITES. The login screen writes
#     its own wrong answer into that same file the first time it runs, so a
#     "leave it alone if it is already there" would fail on precisely the
#     machines that have the problem.
#
# Every test builds a pretend machine in a temporary folder — a pretend DMI name,
# a pretend copy of Bazzite's hardware script, a pretend login-screen home — and
# runs the real script against it. Nothing real is read and nothing real is
# written, so this needs no handheld and no root.
#
# HOW TO RUN IT
#   ./tests/test-aquarius-greeter-scale.sh
#   ./tests/test-aquarius-greeter-scale.sh /usr/libexec/aquarius-greeter-scale
# ==============================================================================

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="${1:-${HERE}/../system_files/usr/libexec/aquarius-greeter-scale}"
SOURCE_JSON="${HERE}/../system_files/usr/share/aquarius/greeter/kwinoutputconfig.json"

if [ ! -r "$SCRIPT" ]; then
    echo "test-aquarius-greeter-scale: cannot read ${SCRIPT}" >&2
    exit 1
fi

export LC_ALL=C

PASSED=0
FAILED=0
pass() { PASSED=$((PASSED + 1)); printf '  OK    %s\n' "$1"; }
fail() { FAILED=$((FAILED + 1)); printf '  FAIL  %s\n' "$1"; }
check() { if [ "$2" = "yes" ]; then pass "$1"; else fail "$1"; fi; }

WORK="$(mktemp -d)"
WORK="$(readlink -f "$WORK")"
trap 'rm -rf -- "$WORK"' EXIT

# ------------------------------------------------------------------------------
# Building a pretend machine
# ------------------------------------------------------------------------------
# new_machine <name> <what the machine calls itself> <does Bazzite's own list
#                                                     claim it: yes|no|missing>
#
# "missing" is the case where /usr/libexec/hwsupport/needs-100-scale is not on
# this image at all — worth testing, because our script must not fall over if
# Bazzite ever renames or drops it.
new_machine() {
    local name="$1" product="$2" bazzite_says="$3"
    local root="${WORK}/${name}"

    mkdir -p "${root}/dmi" "${root}/greeter-home" "${root}/etc"
    printf '%s\n' "$product" > "${root}/dmi/product_name"

    case "$bazzite_says" in
        yes)     printf '#!/bin/sh\nexit 0\n' > "${root}/needs-100-scale"
                 chmod 0755 "${root}/needs-100-scale" ;;
        no)      printf '#!/bin/sh\nexit 1\n' > "${root}/needs-100-scale"
                 chmod 0755 "${root}/needs-100-scale" ;;
        missing) : ;;
    esac

    export AQUARIUS_DMI_PRODUCT_FILE="${root}/dmi/product_name"
    export AQUARIUS_NEEDS_100_SCALE="${root}/needs-100-scale"
    export AQUARIUS_GREETER_HOME="${root}/greeter-home"
    export AQUARIUS_GREETER_USER="nobody-that-exists"
    export AQUARIUS_GREETER_SOURCE="$SOURCE_JSON"
    export AQUARIUS_GREETER_OFF_SWITCH="${root}/etc/no-greeter-scale"

    GREETER_FILE="${root}/greeter-home/.config/kwinoutputconfig.json"
}

asks_for_fix() { "$SCRIPT" --check-device > /dev/null 2>&1; }
run_it()       { "$SCRIPT" > /dev/null 2>&1; }
yesno()        { if "$@"; then echo yes; else echo no; fi; }

# ==============================================================================
echo "Which machines get their login screen adjusted"
echo "----------------------------------------------------------------------"
# ==============================================================================

new_machine ally "ROG Xbox Ally RC73YA" no
check "the ROG Xbox Ally is fixed, even though Bazzite's own list misses it" \
      "$(yesno asks_for_fix)"

new_machine allyx "ROG Xbox Ally X RC73XA" no
check "...and so is the Ally X, which shares the name" \
      "$(yesno asks_for_fix)"

new_machine deck "Jupiter" yes
check "a machine on Bazzite's own do-not-magnify list is fixed" \
      "$(yesno asks_for_fix)"

new_machine pc "B650 AORUS ELITE AX" no
check "an ordinary desktop PC is left completely alone" \
      "$([ "$(yesno asks_for_fix)" = no ] && echo yes || echo no)"

new_machine laptop "ThinkPad X1 Carbon Gen 11" no
check "...and so is a laptop, which has a lid and gets this right by itself" \
      "$([ "$(yesno asks_for_fix)" = no ] && echo yes || echo no)"

new_machine nolist "ROG Xbox Ally RC73YA" missing
check "we still recognise the Ally if Bazzite's script is not on the image" \
      "$(yesno asks_for_fix)"

new_machine nolistpc "B650 AORUS ELITE AX" missing
check "...and a PC is still left alone in that case" \
      "$([ "$(yesno asks_for_fix)" = no ] && echo yes || echo no)"

new_machine noname "" no
check "a machine that will not say what it is, is left alone" \
      "$([ "$(yesno asks_for_fix)" = no ] && echo yes || echo no)"

# A near-miss that must NOT match: prefix matching has to be anchored at the
# start, or a machine whose name merely CONTAINS the words would be caught.
new_machine nearmiss "Definitely Not A ROG Xbox Ally" no
check "a name that only mentions the Ally partway through does not match" \
      "$([ "$(yesno asks_for_fix)" = no ] && echo yes || echo no)"

# ==============================================================================
echo
echo "The off switch"
echo "----------------------------------------------------------------------"
# ==============================================================================

new_machine offswitch "ROG Xbox Ally RC73YA" yes
touch "$AQUARIUS_GREETER_OFF_SWITCH"
check "one file turns the whole thing off, even on a machine that needs it" \
      "$([ "$(yesno asks_for_fix)" = no ] && echo yes || echo no)"
run_it
check "...and nothing is written when it is off" \
      "$([ ! -e "$GREETER_FILE" ] && echo yes || echo no)"

# ==============================================================================
echo
echo "What it actually writes"
echo "----------------------------------------------------------------------"
# ==============================================================================

new_machine writing "ROG Xbox Ally RC73YA" no
run_it
check "the login screen's settings file is created" \
      "$([ -f "$GREETER_FILE" ] && echo yes || echo no)"
check "...and it is exactly the file we ship, byte for byte" \
      "$(yesno cmp -s "$SOURCE_JSON" "$GREETER_FILE")"
check "...saying the built-in screen is not to be magnified" \
      "$(yesno grep -q '"scale": 1' "$GREETER_FILE")"
check "...and naming the built-in screen the way Wayland names it" \
      "$(yesno grep -q '"connectorName": "eDP-1"' "$GREETER_FILE")"

# THE IMPORTANT ONE. The login screen saves its own wrong answer into this same
# file the first time it runs, so anything that respects an existing file would
# never fix a machine that has already been switched on — which is all of them.
printf '[{"name":"outputs","data":[{"connectorName":"eDP-1","scale":2.1}]}]\n' \
    > "$GREETER_FILE"
run_it
check "a wrong answer the login screen saved earlier is overwritten, not respected" \
      "$(yesno cmp -s "$SOURCE_JSON" "$GREETER_FILE")"

# Running twice must be safe and must leave the same result.
run_it
check "running it again changes nothing and breaks nothing" \
      "$(yesno cmp -s "$SOURCE_JSON" "$GREETER_FILE")"

new_machine notouching "B650 AORUS ELITE AX" no
run_it
check "on a desktop PC it writes nothing at all" \
      "$([ ! -e "$GREETER_FILE" ] && echo yes || echo no)"
check "...and still finishes successfully, so nothing goes red on a good machine" \
      "$(yesno run_it)"

# ==============================================================================
echo
echo "The file we ship"
echo "----------------------------------------------------------------------"
# ==============================================================================

check "it is there in the repo" "$([ -f "$SOURCE_JSON" ] && echo yes || echo no)"
if command -v python3 > /dev/null 2>&1; then
    check "it is valid JSON — KWin discards a file it cannot read, silently" \
          "$(yesno python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$SOURCE_JSON")"
    # KWin throws away any output entry with no way to identify the screen, so
    # the connectorName key is not decoration.
    check "every screen in it is identified, or KWin would throw the entry away" \
          "$(yesno python3 -c '
import json, sys
blocks = json.load(open(sys.argv[1]))
outputs = next(b["data"] for b in blocks if b["name"] == "outputs")
ids = ("edidIdentifier", "edidHash", "connectorName", "mstPath")
sys.exit(0 if outputs and all(any(k in o for k in ids) for o in outputs) else 1)
' "$SOURCE_JSON")"
fi

echo
echo "${PASSED} passed, ${FAILED} failed"
[ "$FAILED" -eq 0 ]
