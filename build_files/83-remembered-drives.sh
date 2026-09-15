#!/usr/bin/bash
# ==============================================================================
# STEP 83 — An inside drive asks ONCE, and then opens at every login
# ==============================================================================
# WHAT THIS STEP IS FOR
#
# Step 76 is about the drives you PLUG IN: they appear on their own and never
# ask for a password. This step is about the drives that live INSIDE the
# machine — a second SSD full of footage, the disk Windows is on.
#
# Those have always asked for an administrator password, every login, for a good
# reason: mounting an internal disk is not something that should happen behind
# anybody's back. Right the first time; annoying the tenth. So since
# 2026-09-14 (FEATURES 020) AquariusOS asks ONCE, per drive:
#
#     Mount "Footage" every login?
#     [ Mount every login ]  [ Never ask ]     (closing it means "not now")
#
# "Mount every login" writes one line into /etc/fstab, keyed by the drive's
# UUID. After that the machine mounts it itself, before anybody logs in, and no
# password is ever asked again — because a drive in fstab does not go through
# polkit at all.
#
# ⚠️ AND THE THING THAT DELIBERATELY DID NOT CHANGE, WHICH IS THE WHOLE DESIGN.
# The obvious way to stop internal disks asking is to widen the no-password rule
# in 49-aquarius-udisks.rules to cover `filesystem-mount-system`. That would
# make EVERY internal partition on the machine mountable with no password,
# including ones nobody ever chose, and step 76 STOPS THE BUILD if that action
# name ever appears in that rule's code. That gate is untouched and stays
# untouched. This feature exists so it never has to move.
#
# THE FOUR PIECES THIS STEP CHECKS
#
#   1. /usr/libexec/aquarius-remember-drive — the privileged helper that writes
#      the fstab line. It carries its own copy of the never-touch list, because
#      a privileged program must not believe what it was told.
#   2. Two polkit files of ours — an ACTION (what the job is, and that it needs
#      an administrator password) and a RULE (only the person at this screen, in
#      the active local session, in the `wheel` group).
#   3. The session agent's half: /usr/libexec/aquarius-automount now puts the
#      question on screen, and still mounts no internal disk itself.
#   4. tests/test-remember-drive.py, run against the finished image, which is
#      mostly a list of drives that must NEVER be offered.
#
# Plain-English guide: docs/restart/hardware.md, section "Why an inside drive
# asks once, and an outside drive never asks".
# ==============================================================================

# shellcheck source=build_files/aq-lib.sh
source "$(dirname "$0")/aq-lib.sh"

HELPER="/usr/libexec/aquarius-remember-drive"
AGENT="/usr/libexec/aquarius-automount"
ACTION="/usr/share/polkit-1/actions/org.aquariusos.rememberdrive.policy"
RULE="/usr/share/polkit-1/rules.d/50-aquarius-remember-drive.rules"
UDISKS_RULE="/usr/share/polkit-1/rules.d/49-aquarius-udisks.rules"

# ------------------------------------------------------------------------------
# 1. The privileged helper — present, valid Python, and able to state its rules
# ------------------------------------------------------------------------------
say "The helper that remembers an inside drive"
if [ -x "${HELPER}" ]; then
    ok "${HELPER} is present and runnable"
else
    bad "${HELPER} is missing or not runnable — saying yes to the question would do nothing"
fi

if python3 -c 'import py_compile, sys; py_compile.compile(sys.argv[1], cfile="/tmp/aq-remember.pyc", doraise=True)' "${HELPER}" 2> /tmp/aq-remember-py.txt; then
    ok "the helper is valid Python"
else
    bad "the helper has a syntax error:"
    sed 's/^/       /' /tmp/aq-remember-py.txt
fi
rm -f /tmp/aq-remember.pyc /tmp/aq-remember-py.txt

# --dry-run is designed to run HERE: no drives, no fstab worth reading, no root.
# It states the never-touch list, and the list is the safety of the feature, so
# it is read back word by word. A future edit that quietly drops "the EFI
# partition" from the list is caught here.
say "The helper's rehearsal (--dry-run), and the never-touch list it states"
if "${HELPER}" --dry-run > /tmp/aq-remember-dry.txt 2>&1; then
    ok "'aquarius-remember-drive --dry-run' runs and changes nothing"
    sed 's/^/       /' /tmp/aq-remember-dry.txt
else
    bad "'aquarius-remember-drive --dry-run' failed — the helper cannot load in this image:"
    sed 's/^/       /' /tmp/aq-remember-dry.txt
fi

aq_file_has /tmp/aq-remember-dry.txt 'disk AquariusOS is installed on' \
    "the rehearsal says it will never remember the disk the OS is on"
aq_file_has /tmp/aq-remember-dry.txt 'EFI partition' \
    "the rehearsal says it will never remember the EFI partition"
aq_file_has /tmp/aq-remember-dry.txt 'swap' \
    "the rehearsal says it will never remember swap, LUKS, LVM or RAID"
aq_file_has /tmp/aq-remember-dry.txt "Windows' system volume" \
    "the rehearsal says it will never remember Windows' own volume"
aq_file_has /tmp/aq-remember-dry.txt 'BitLocker' \
    "the rehearsal names BitLocker, which it refuses rather than guesses at"
aq_file_has /tmp/aq-remember-dry.txt 'already named in /etc/fstab' \
    "the rehearsal says it will not remember something already in fstab"
aq_file_has /tmp/aq-remember-dry.txt 'READ-ONLY' \
    "the rehearsal says NTFS drives are remembered read-only"
aq_file_has /tmp/aq-remember-dry.txt 'nofail' \
    "the rehearsal names nofail — a missing drive must never stop the computer starting"
aq_file_has /tmp/aq-remember-dry.txt 'x-systemd.automount' \
    "the rehearsal names x-systemd.automount — nothing waits on a slow disk at boot"
aq_file_has /tmp/aq-remember-dry.txt '49-aquarius-udisks.rules' \
    "the rehearsal states, in its own words, that it never widens the udisks rule"
rm -f /tmp/aq-remember-dry.txt

# ------------------------------------------------------------------------------
# 2. The two polkit files, and what they must and must not say
# ------------------------------------------------------------------------------
say "Who is allowed to remember a drive"
if [ -r "${ACTION}" ]; then
    ok "${ACTION} is installed"
else
    bad "${ACTION} is missing — pkexec would refuse the helper with 'not authorized'"
fi

aq_file_has "${ACTION}" 'org\.aquariusos\.rememberdrive\.manage' \
    "the action file names the job the helper is started for"
aq_file_has "${ACTION}" '<allow_active>auth_admin_keep</allow_active>' \
    "an administrator password is asked for — and remembered only for polkit's own short window"
aq_file_has "${ACTION}" '<allow_any>no</allow_any>' \
    "nobody who is not sitting at this machine may do it"
aq_file_has "${ACTION}" '<allow_inactive>no</allow_inactive>' \
    "not even from a session that has been switched away from"
aq_file_has "${ACTION}" "org\.freedesktop\.policykit\.exec\.path</annotate>" \
    "the action is tied to one program on disk, so nothing else can borrow it"
aq_file_has "${ACTION}" "${HELPER}" \
    "and that program is ${HELPER}"

if [ -r "${RULE}" ]; then
    ok "${RULE} is installed"
else
    bad "${RULE} is missing — anybody in wheel could be asked, from anywhere"
fi
aq_file_has "${RULE}" 'subject\.local' \
    "the rule is limited to the LOCAL session (not someone over SSH)"
aq_file_has "${RULE}" 'subject\.active' \
    "the rule is limited to the ACTIVE session (the one at the screen now)"
aq_file_has "${RULE}" 'subject\.isInGroup\("wheel"\)' \
    "and to an administrator"
aq_file_has "${RULE}" 'polkit\.Result\.AUTH_ADMIN_KEEP' \
    "who is asked for their password (once, for several drives)"
aq_file_has "${RULE}" 'polkit\.Result\.NO' \
    "and everybody else is refused outright, with no password box at all"

# ⚠️ THE SAME "WHAT IT MUST NEVER SAY" GATE AS STEP 76, ON THE NEW FILE. This
# rule is about OUR action and nothing else. If udisks2's internal-disk action
# ever turns up in it, somebody has moved the fence while nobody was looking —
# and they would have done it in the file the 76 gate does not read. Comments
# are stripped first, for the same reason they are stripped in step 76: the
# explanation may name the thing it is explaining.
if sed 's://.*::' "${RULE}" | grep -q 'filesystem-mount-system'; then
    bad "${RULE} mentions filesystem-mount-system in its code. That is the thing"
    bad "this whole feature exists to avoid. Remove it; internal disks stay as they are."
else
    ok "the new rule says nothing about udisks2's internal-disk action either"
fi

# And the old rule is STILL what it was. Step 76 owns that check; this is the
# cheap restatement, here so that a person reading this step can see with their
# own eyes that the narrow rule was not the price of this feature.
if sed 's://.*::' "${UDISKS_RULE}" | grep -q 'filesystem-mount-system'; then
    bad "${UDISKS_RULE} has been widened after all — see build_files/76-automount.sh."
else
    ok "⚠️ and 49-aquarius-udisks.rules is STILL silent about internal disks, which"
    ok "   is the entire point of doing it this way"
fi

# ------------------------------------------------------------------------------
# 3. The agent's half — it asks, and it still mounts no internal disk itself
# ------------------------------------------------------------------------------
say "The session agent's half of the question"
if "${AGENT}" --dry-run > /tmp/aq-automount-dry2.txt 2>&1; then
    ok "'aquarius-automount --dry-run' still runs"
else
    bad "'aquarius-automount --dry-run' failed:"
    sed 's/^/       /' /tmp/aq-automount-dry2.txt
fi
aq_file_has /tmp/aq-automount-dry2.txt 'HintSystem = false' \
    "the agent STILL says it leaves system-internal disks alone (unchanged from step 76)"
aq_file_has /tmp/aq-automount-dry2.txt 'never mounts by itself' \
    "and says out loud that an inside drive is asked about, never mounted by it"
aq_file_has /tmp/aq-automount-dry2.txt 'Never ask' \
    "the rehearsal names the three answers a person can give"
aq_file_has /tmp/aq-automount-dry2.txt "${HELPER}" \
    "and names the privileged helper it hands a 'yes' to"
aq_file_has /tmp/aq-automount-dry2.txt 'EFI partition' \
    "the agent's rehearsal states the never-touch list too"
aq_file_has /tmp/aq-automount-dry2.txt "Windows' system volume" \
    "including Windows' own volume"
aq_file_has /tmp/aq-automount-dry2.txt '49-aquarius-udisks.rules' \
    "and states that it never widens the udisks rule"
rm -f /tmp/aq-automount-dry2.txt

# The two programs the answer depends on. Without pkexec there is nothing to ask
# with; without notify-send there is no question at all.
if [ -x /usr/bin/pkexec ]; then
    ok "pkexec is present — the 'yes' button has something to ask with"
else
    bad "/usr/bin/pkexec is missing — saying yes could never reach the helper"
fi
if [ -x /usr/bin/notify-send ]; then
    ok "notify-send is present — the question can appear on screen"
else
    bad "/usr/bin/notify-send is missing — nobody would ever be asked"
fi
# `--action` (the buttons) needs libnotify 0.8 or newer. Without it the question
# still appears, without buttons — which is a real loss, so it is said out loud
# rather than passed over.
if notify-send --help 2>&1 | grep -q -- '--action'; then
    ok "and this notify-send has --action, so the question really has buttons"
else
    bad "this notify-send has no --action: the question would appear with no"
    bad "buttons and nobody could answer it. Check libnotify's version."
fi

# The friendly way to undo a choice.
say "The undo: 'aq drives remembered' and 'aq drives forget'"
aq_file_has /usr/bin/aq 'AQ_REMEMBER_DRIVE="/usr/libexec/aquarius-remember-drive"' \
    "aq knows where the helper is"
aq_file_has /usr/bin/aq '^        remembered \| remember\) drive_remembered ;;$' \
    "'aq drives remembered' lists what is remembered"
aq_file_has /usr/bin/aq '^        forget\) drive_forget ' \
    "'aq drives forget NAME' takes one back out"
aq_file_has /usr/bin/aq '^        ask-again \| askagain\) drive_ask_again ;;$' \
    "'aq drives ask-again' undoes a 'Never ask'"
aq_file_has /usr/bin/aq 'aq drives remembered  Which inside drives' \
    "and all three are in 'aq drives --help', so they can be found"

# ------------------------------------------------------------------------------
# 4. The test — mostly a list of drives that must NEVER be offered
# ------------------------------------------------------------------------------
# Same reasoning as step 76's mount test: the dangerous half of this feature is
# the drives it must refuse, and no amount of reading proves a refusal. This
# runs the real decision code against fake drives — an EFI partition, a
# partition of the system disk, a swap area, a drive with no UUID — inside the
# finished image, with the Python that is really in it.
say "The decision itself, against fake drives (the refusals are the point)"
if [ -r /ctx/tests/test-remember-drive.py ]; then
    # -B for the same reason step 76 uses it: Python must not leave a
    # __pycache__ folder in /usr/libexec of the finished image.
    if python3 -B /ctx/tests/test-remember-drive.py "${AGENT}" "${HELPER}"; then
        ok "the right drives are offered, and the wrong ones are refused"
    else
        bad "a drive that must never be offered was offered, or one that should"
        bad "be was not. See the lines above — this is the safety of the feature."
    fi
    rm -rf /usr/libexec/__pycache__ /usr/lib/aquarius/python/__pycache__
else
    bad "/ctx/tests/test-remember-drive.py is missing — the only check that proves a refusal"
fi

aq_finish "Inside drives are remembered, once"
