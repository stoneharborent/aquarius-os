#!/usr/bin/bash
# ==============================================================================
# STEP 76 — External drives mount by themselves, with no password
# ==============================================================================
# WHAT THIS STEP IS FOR
#
# On AquariusOS, plugging in a USB stick, an SD card or an external SSD makes it
# appear on its own — no password, and you eject it from the dock the same way.
# That is what a creator coming off a Mac expects, and it is four pieces:
#
#   1. udisks2 — Fedora's drive-mounting service. It is already installed by
#      step 20 (the hardware/media floor); this step confirms it, because the
#      other three are useless without it.
#   2. A small agent, /usr/libexec/aquarius-automount, that runs in the person's
#      session, watches udisks2 for a drive being plugged in, and asks it to
#      mount. This is the piece Fedora does not provide on its own.
#   3. A polkit rule, /usr/share/polkit-1/rules.d/49-aquarius-udisks.rules, that
#      lets the person at the screen mount/unmount/eject a REMOVABLE drive with
#      no password — and, on purpose, does NOT do that for internal disks.
#   4. A user service, wired on for both desktops, that starts the agent.
#
# Pieces 2, 3 and 4 arrived in the image as plain files at step 50 (which copies
# everything under system_files/ into place). This step CHECKS the whole thing,
# because a drive that silently will not mount, or a password box for a USB
# stick, is exactly the kind of fault nobody sees until the one moment it
# matters.
#
# The filesystems those drives are formatted as — exFAT for camera cards, NTFS
# for Windows drives — are installed and checked by step 20. APFS (a Mac drive)
# is deliberately out of scope: it needs apfs-fuse and is read-only, which is a
# later decision, not this feature.
#
# Plain-English guide: docs/restart/hardware.md, section "Plugging a drive in —
# and the bug that meant we never did".
# ==============================================================================

# shellcheck source=build_files/aq-lib.sh
source "$(dirname "$0")/aq-lib.sh"

AGENT="/usr/libexec/aquarius-automount"
UNIT="/usr/lib/systemd/user/aquarius-automount.service"
WANTS_LINK="/usr/lib/systemd/user/graphical-session.target.wants/aquarius-automount.service"
RULE="/usr/share/polkit-1/rules.d/49-aquarius-udisks.rules"

# ------------------------------------------------------------------------------
# 1. The machinery that actually mounts drives, and the filesystems it reads
# ------------------------------------------------------------------------------
say "The drive-mounting service and the filesystems creators plug in"
aq_installed \
    udisks2 \
    exfatprogs \
    ntfs-3g

# polkit itself has to be here, or a rule file is just text nobody reads.
aq_installed polkit

# ------------------------------------------------------------------------------
# 2. The agent — present, valid Python, and runnable with no screen
# ------------------------------------------------------------------------------
say "The auto-mount agent"
if [ -x "${AGENT}" ]; then
    ok "${AGENT} is present and runnable"
else
    bad "${AGENT} is missing or not runnable — nothing would mount a drive on insert"
fi

# It is Python. A syntax error must stop the build, not wait for a login.
if python3 -c 'import py_compile, sys; py_compile.compile(sys.argv[1], cfile="/tmp/aq-automount.pyc", doraise=True)' "${AGENT}" 2> /tmp/aq-automount-py.txt; then
    ok "the agent is valid Python"
else
    bad "the agent has a syntax error:"
    sed 's/^/       /' /tmp/aq-automount-py.txt
fi
rm -f /tmp/aq-automount.pyc /tmp/aq-automount-py.txt

# --dry-run is designed to work HERE — in a build container with no udisks2 and
# no system bus. It imports gi (proving python3-gobject is in the image), states
# its rules, and exits 0 without touching D-Bus. If this fails, the agent could
# not even load on a real machine.
say "The agent's rehearsal (--dry-run), which is what proves it loads"
if "${AGENT}" --dry-run > /tmp/aq-automount-dry.txt 2>&1; then
    ok "'aquarius-automount --dry-run' runs and changes nothing"
    sed 's/^/       /' /tmp/aq-automount-dry.txt
else
    bad "'aquarius-automount --dry-run' failed — the agent cannot load in this image:"
    sed 's/^/       /' /tmp/aq-automount-dry.txt
fi
# The rehearsal must state the safety rules, so a future edit that drops the
# HintSystem guard is caught here rather than on a machine that mounts its own
# boot disk twice.
aq_file_has /tmp/aq-automount-dry.txt 'HintSystem = false' \
    "the agent's own rehearsal states that it leaves system-internal disks alone"
aq_file_has /tmp/aq-automount-dry.txt 'no password' \
    "the agent's rehearsal states that mounting needs no password"
rm -f /tmp/aq-automount-dry.txt

# ------------------------------------------------------------------------------
# ⚠️ AND THE ONE CHECK THAT WOULD HAVE CAUGHT THE BENCH FAULT: really mount
# ------------------------------------------------------------------------------
# THE FAULT, 2026-09-08. Royce plugged in his drives; they appeared in Files but
# not in the dock. The agent had crashed on EVERY mount since it shipped:
#
#     File ".../gi/overrides/GLib.py", line 396, in __getitem__
#     KeyError: 0
#
# One line built udisks2's Mount argument the wrong way round — a GLib.Variant
# wrapped inside another GLib.Variant, where PyGObject wants a plain dictionary.
# The two drives in /run/media had been mounted by the Files app, not by us.
#
# ⚠️ AND WHY THIS STEP DID NOT NOTICE. The two checks above are `py_compile` and
# "can Python import gi". Both passed, on every build, for five days. The broken
# line was perfectly valid Python and the fault only exists at the moment
# PyGObject actually builds the value — which nothing in this build ever asked
# it to do. A check that cannot fail is not a check.
#
# So tests/test-automount-mount.py calls mount() for real against a fake bus.
# The Variant is genuinely constructed, by the same PyGObject that is in this
# image, and the argument's type string is read back and compared. It also proves
# a refused mount logs a plain sentence instead of a traceback, and that an
# unexpected error — the exact shape of the fault above — is caught rather than
# escaping.
say "The agent really mounts a drive (against a fake bus)"
if [ -r /ctx/tests/test-automount-mount.py ]; then
    if python3 /ctx/tests/test-automount-mount.py "${AGENT}"; then
        ok "the agent asks udisks2 to mount, in the shape udisks2 expects"
    else
        bad "the agent would NOT mount a drive — see the lines above. This is the"
        bad "2026-09-08 bench fault: drives appear in Files and never in the dock."
    fi
else
    bad "/ctx/tests/test-automount-mount.py is missing — the only check that proves a drive is really mounted"
fi

# Python must be able to reach GLib and Gio in this image — the two the agent
# imports. This is the automount equivalent of the GTK import check the Resolve
# window has, and it catches a missing python3-gobject.
if python3 -c 'import gi; gi.require_version("GLib","2.0"); gi.require_version("Gio","2.0"); from gi.repository import GLib, Gio' 2> /tmp/aq-gi.txt; then
    ok "Python can reach GLib and Gio — the agent's only dependency"
else
    bad "Python cannot import GLib and Gio — the agent would not run"
    sed 's/^/       /' /tmp/aq-gi.txt
fi
rm -f /tmp/aq-gi.txt
aq_installed python3-gobject

# ⚠️ AND THE SHAPE ITSELF, READ BACK OUT OF THE FILE. The test above is the real
# guard; this is the cheap one that names the mistake, so that a future edit
# reintroducing it is refused with the reason attached rather than with a type
# string nobody can read.
# Comment lines are dropped before looking, because the agent's own comment
# quotes the wrong shape to explain it — and the first build of this check
# (run 34299873627) failed on exactly that quotation.
if grep -v '^[[:space:]]*#' "${AGENT}" | grep -q 'GLib.Variant("(a{sv})", (options,))' \
    && grep -v '^[[:space:]]*#' "${AGENT}" | grep -q 'options = GLib.Variant("a{sv}"'; then
    bad "the agent wraps a GLib.Variant inside another GLib.Variant again — that is"
    bad "the 2026-09-08 'KeyError: 0' and it kills every mount. Pass a plain dict."
elif grep -v '^[[:space:]]*#' "${AGENT}" | grep -q '^[[:space:]]*options = {'; then
    ok "the mount options are a plain dictionary, not a Variant inside a Variant"
else
    bad "could not find 'options = {' in the agent — the mount-options shape has changed; read mount() and update this check"
fi

# ------------------------------------------------------------------------------
# 3. The polkit rule — scoped tightly, and NOT a blanket allow
# ------------------------------------------------------------------------------
# This is the security-sensitive part, so it is checked in both directions:
# what it MUST say, and what it must NEVER say.
say "The no-password rule, and the limits on it"
if [ -r "${RULE}" ]; then
    ok "${RULE} is installed"
else
    bad "${RULE} is missing — mounting a drive would ask for a password"
fi

# What it must say: only the person physically at the machine, only in the
# session that owns the screen, and a YES for mounting a removable drive.
aq_file_has "${RULE}" 'subject\.local' \
    "the rule is limited to the LOCAL session (not someone over SSH)"
aq_file_has "${RULE}" 'subject\.active' \
    "the rule is limited to the ACTIVE session (the one at the screen now)"
aq_file_has "${RULE}" 'org\.freedesktop\.udisks2\.filesystem-mount' \
    "the rule allows mounting a removable filesystem"
aq_file_has "${RULE}" 'org\.freedesktop\.udisks2\.eject-media' \
    "the rule allows ejecting removable media"
aq_file_has "${RULE}" 'polkit\.Result\.YES' \
    "the rule actually grants something (returns YES)"

# ⚠️ What it must NEVER say. The whole safety of this feature is that mounting a
# SYSTEM-INTERNAL disk still needs a password — udisks2 checks a different
# action for those (filesystem-mount-system), and this rule's CODE must stay
# silent about it so the request falls through to the default that asks for auth.
# If that action name ever appears in the code, someone has widened a narrow
# rule into a blanket "mount anything with no password", and the build must stop.
#
# The comments in the rule DO mention filesystem-mount-system — they explain why
# it is deliberately absent — so we strip the `//` comments before checking, or
# the explanation would trip the alarm it is describing.
if sed 's://.*::' "${RULE}" | grep -q 'filesystem-mount-system'; then
    bad "${RULE} grants filesystem-mount-system in its code — that would let an"
    bad "INTERNAL disk be mounted with no password. Remove it: internal disks must ask."
else
    ok "the rule's code says nothing about internal disks (filesystem-mount-system) — so they still need a password"
fi

# polkit refuses to load a rule file it cannot parse, silently, at runtime. If
# the tool that checks that is in the image, use it; if not, say so honestly
# rather than claim a check that did not run (the aq-lib.sh rule).
if aq_have polkit; then
    :
fi
if [ -x /usr/bin/pkcheck ] || [ -x /usr/lib/polkit-1/polkitd ]; then
    ok "polkit is present to load this rule at runtime"
else
    bad "polkitd is not in the image — no rule would be read at all"
fi

# ------------------------------------------------------------------------------
# 4. The service, and the fact that it is switched on for both desktops
# ------------------------------------------------------------------------------
say "The service that starts the agent at login"
aq_file_has "${UNIT}" '^ExecStart=/usr/libexec/aquarius-automount$' \
    "the service runs the agent"
aq_file_has "${UNIT}" '^PartOf=graphical-session\.target$' \
    "the service ends when the desktop does"
aq_file_has "${UNIT}" '^WantedBy=graphical-session\.target$' \
    "the service belongs to the graphical session (which both desktops reach)"
aq_file_has "${UNIT}" '^ConditionUser=!@system$' \
    "the LOGIN SCREEN does not run this — only real people, not the gdm account"

# The "switched on" link, shipped in /usr so an update always restores it and no
# local change can silently lose it. Same mechanism, and same trade-off, as
# aquarius-keys — the long explanation is in aq-lib.sh next to
# aq_unit_is_on_from_usr. This is a USER unit, so the check is written out here
# rather than using that helper (which checks the system graphical.target).
if [ -L "${WANTS_LINK}" ]; then
    target="$(readlink "${WANTS_LINK}")"
    echo "  ${WANTS_LINK} -> ${target}"
    if [ -e "${WANTS_LINK}" ]; then
        ok "the service is switched on by default, and the link points at a real file"
    else
        bad "the 'switched on' link is dangling — it points at ${target}, which is not there"
    fi
else
    bad "${WANTS_LINK} is missing — the agent would be installed but never start"
fi

# Nothing of ours may be switched on through /etc — an update could lose that.
if [ -e "/etc/systemd/user/graphical-session.target.wants/aquarius-automount.service" ]; then
    bad "aquarius-automount is ALSO switched on through /etc — a build step ran an enable. See aq-lib.sh."
else
    ok "nothing switches the agent on through /etc"
fi

# systemd's own opinion of the unit file, where it can give one. Advisory, so it
# is printed and only a real parse fault is treated as failure — and, as the
# keys step learned, a container where the manager cannot start is reported
# honestly rather than as a green tick nobody earned.
if aq_have systemd-analyze; then
    say "systemd's own opinion of the service file"
    verdict="$(systemd-analyze verify --user "${UNIT}" 2>&1 || true)"
    printf '%s\n' "${verdict}" | sed 's/^/  /'
    if printf '%s' "${verdict}" | grep -Eqi "failed to initialize manager|failed to lookup runtimedirectory"; then
        echo "  note   systemd-analyze could not start inside this container, so it"
        echo "         did not read the file. The line-by-line checks above are"
        echo "         what actually guard this unit."
    elif printf '%s' "${verdict}" | grep -Eqi "unknown (key|lvalue)|failed to parse"; then
        bad "systemd cannot understand part of ${UNIT} (see above)."
    else
        ok "systemd read the service file and understood every line of it"
    fi
fi

aq_finish "External drives automount"
